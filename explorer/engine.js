// Betting engine for the explorer: a JavaScript port of R/strategies.R,
// R/simulate.R and R/exact.R, so the page needs no download beyond this file.
// explorer/tests/engine.test.js checks it against the R engine on every build.
//
// The exact calculation differs from R/exact.R in one way. Instead of solving
// the Markov chain's equations, it pushes probability forward one spin at a
// time. That gives the same answers, plus the exact state of all players after
// every spin, which is what the explorer's charts draw.

(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.Engine = api;
})(globalThis, function () {
  const P_AMERICAN = 18 / 38;
  const P_EUROPEAN = 18 / 37;

  // Stop following a session once this share of players is still at the table
  const TOLERANCE = 1e-12;
  const MAX_STEPS = 500000;

  const withinLimit = (next, reset, tableMax) => (next > tableMax ? reset : next);

  // Fibonacci numbers, cached because the solver asks for the same few repeatedly
  const fibCache = [0, 1, 1];
  function fib(k) {
    for (let i = fibCache.length; i <= k; i++) fibCache[i] = fibCache[i - 1] + fibCache[i - 2];
    return fibCache[k];
  }

  // Each strategy mirrors its R counterpart. Memory is a single number: the next
  // bet, or the position in the Fibonacci sequence. Flat bets and bold play need none.
  const STRATEGIES = {
    flat: {
      name: "Flat bets",
      init: () => 0,
      stake: (mem, cash, goal, unit) => unit,
      update: (mem) => mem,
    },
    martingale: {
      name: "Martingale",
      init: (unit) => unit,
      stake: (mem) => mem,
      update: (mem, won, unit, tableMax) => (won ? unit : withinLimit(2 * mem, unit, tableMax)),
    },
    reverse_martingale: {
      name: "Reverse Martingale",
      init: (unit) => unit,
      stake: (mem) => mem,
      update: (mem, won, unit, tableMax) => (won ? withinLimit(2 * mem, unit, tableMax) : unit),
    },
    dalembert: {
      name: "D'Alembert",
      init: (unit) => unit,
      stake: (mem) => mem,
      update: (mem, won, unit, tableMax) =>
        won ? Math.max(unit, mem - unit) : withinLimit(mem + unit, unit, tableMax),
    },
    fibonacci: {
      name: "Fibonacci",
      init: () => 1,
      stake: (mem, cash, goal, unit) => unit * fib(mem),
      update: (mem, won, unit, tableMax) => {
        if (won) return Math.max(1, mem - 2);
        return unit * fib(mem + 1) > tableMax ? 1 : mem + 1;
      },
    },
    bold_play: {
      name: "Bold play",
      init: () => 0,
      stake: (mem, cash, goal, unit, tableMax) => Math.min(cash, goal - cash, tableMax),
      update: (mem) => mem,
    },
  };

  const placedBet = (s, mem, cash, goal, unit, tableMax) =>
    Math.min(s.stake(mem, cash, goal, unit, tableMax), cash);

  // List every state (cash, memory) a session can reach, and where each spin leads.
  // A next-state of -1 means the session ended: broke on a loss, at the goal on a win.
  function buildChain(strategy, bankroll, unit, goal, tableMax) {
    const index = new Map();
    const cash = [];
    const mem = [];
    const bet = [];
    const onWin = [];
    const onLose = [];
    const winCash = []; // final cash when a win ends the session

    const lookup = (c, m) => {
      const key = c * 1e7 + m;
      let id = index.get(key);
      if (id === undefined) {
        id = cash.length;
        index.set(key, id);
        cash.push(c);
        mem.push(m);
      }
      return id;
    };

    lookup(bankroll, strategy.init(unit));
    for (let i = 0; i < cash.length; i++) {
      const b = placedBet(strategy, mem[i], cash[i], goal, unit, tableMax);
      bet[i] = b;
      const up = cash[i] + b;
      const down = cash[i] - b;
      if (up >= goal) {
        onWin[i] = -1;
        winCash[i] = up;
      } else {
        onWin[i] = lookup(up, strategy.update(mem[i], true, unit, tableMax));
        winCash[i] = 0;
      }
      onLose[i] = down > 0 ? lookup(down, strategy.update(mem[i], false, unit, tableMax)) : -1;
    }

    return {
      n: cash.length,
      cash: Float64Array.from(cash),
      bet: Float64Array.from(bet),
      onWin: Int32Array.from(onWin),
      onLose: Int32Array.from(onLose),
      winCash: Float64Array.from(winCash),
    };
  }

  // Push the share of players in each state forward one spin at a time.
  // visit(spin, shares), if given, sees the shares after each spin.
  function propagate(chain, p, maxSpins, visit) {
    const q = 1 - p;
    let now = new Float64Array(chain.n);
    let next = new Float64Array(chain.n);
    now[0] = 1;

    let won = 0;
    let broke = 0;
    let finalCash = 0;
    let wagered = 0;
    let spins = 0;
    const wonBySpin = [0];
    const brokeBySpin = [0];

    for (let t = 1; t <= maxSpins; t++) {
      next.fill(0);
      let alive = 0;
      for (let i = 0; i < chain.n; i++) {
        const share = now[i];
        if (share === 0) continue;
        alive += share;
        wagered += share * chain.bet[i];
        const w = chain.onWin[i];
        if (w >= 0) next[w] += share * p;
        else {
          won += share * p;
          finalCash += share * p * chain.winCash[i];
        }
        const l = chain.onLose[i];
        if (l >= 0) next[l] += share * q;
        else broke += share * q;
      }
      spins += alive;
      wonBySpin.push(won);
      brokeBySpin.push(broke);
      [now, next] = [next, now];
      if (visit) visit(t, now);
      if (alive < TOLERANCE) break;
    }

    return { won, broke, finalCash, wagered, spins, wonBySpin, brokeBySpin };
  }

  // Exact results for one strategy, matching solve_exact() in R/exact.R.
  // status holds the exact share of players won and broke after every spin.
  function solveExact(strategy, bankroll, p, unit, goal, tableMax = Infinity) {
    const chain = buildChain(strategy, bankroll, unit, goal, tableMax);
    const r = propagate(chain, p, MAX_STEPS);
    return {
      pGoal: r.won,
      expWagered: r.wagered,
      expSpins: r.spins,
      expResult: r.finalCash - bankroll,
      nStates: chain.n,
      chain,
      status: { won: r.wonBySpin, broke: r.brokeBySpin },
    };
  }

  // Exact heat map: the average share of all players holding each cash range,
  // for spins grouped into nx columns and cash in rows band dollars tall. Players
  // who have finished are not counted. Keep band a whole number of bets: otherwise
  // rows hold uneven numbers of cash amounts, which shows up as stripes.
  function exactDensity(chain, p, maxSpin, goal, nx, band) {
    nx = Math.min(nx, maxSpin);
    const ny = Math.ceil(goal / band);
    const cells = new Float64Array(nx * ny);
    const spinsInColumn = new Float64Array(nx);
    const row = new Int32Array(chain.n);
    for (let i = 0; i < chain.n; i++) {
      row[i] = Math.min(Math.floor(chain.cash[i] / band), ny - 1);
    }
    propagate(chain, p, maxSpin, (t, shares) => {
      const col = Math.min(Math.floor(((t - 1) / maxSpin) * nx), nx - 1);
      spinsInColumn[col]++;
      for (let i = 0; i < chain.n; i++) {
        if (shares[i] > 0) cells[row[i] * nx + col] += shares[i];
      }
    });
    for (let y = 0; y < ny; y++) {
      for (let x = 0; x < nx; x++) {
        if (spinsInColumn[x] > 0) cells[y * nx + x] /= spinsInColumn[x];
      }
    }
    return { cells, nx, ny, band, top: ny * band, maxSpin };
  }

  // Small seeded random number generator (mulberry32), so the same settings
  // always show the same simulated players.
  function makeRandom(seed) {
    let a = seed >>> 0;
    return function () {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // Play one session spin by spin, as simulate_player() does in R/simulate.R.
  function simulatePlayer(strategy, bankroll, p, unit, goal, tableMax, random, keepPath = false) {
    let cash = bankroll;
    let peak = bankroll;
    let spins = 0;
    let wagered = 0;
    let mem = strategy.init(unit);
    const path = keepPath ? [bankroll] : null;

    while (cash > 0 && cash < goal) {
      const bet = placedBet(strategy, mem, cash, goal, unit, tableMax);
      const won = random() < p;
      cash += won ? bet : -bet;
      wagered += bet;
      spins++;
      if (cash > peak) peak = cash;
      mem = strategy.update(mem, won, unit, tableMax);
      if (keepPath) path.push(cash);
    }

    return { spins, final: cash, peak, wagered, reachedGoal: cash >= goal, path };
  }

  const median = (values) => {
    const sorted = Float64Array.from(values).sort();
    const mid = sorted.length >> 1;
    return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  };

  // Simulate n players. Each has its own seed, so the typical player (closest to
  // the median on peak cash and session length) can be replayed to draw their path.
  function simulateMany(n, strategy, bankroll, p, unit, goal, tableMax, seed = 1) {
    const players = [];
    for (let i = 0; i < n; i++) {
      players.push(simulatePlayer(strategy, bankroll, p, unit, goal, tableMax, makeRandom(seed + i)));
    }
    const midPeak = median(players.map((x) => x.peak));
    const midSpins = median(players.map((x) => x.spins));
    let best = 0;
    let bestDistance = Infinity;
    players.forEach((x, i) => {
      const distance = Math.abs(Math.log(x.peak / midPeak)) + Math.abs(Math.log(x.spins / midSpins));
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    });
    const typical = simulatePlayer(strategy, bankroll, p, unit, goal, tableMax, makeRandom(seed + best), true);
    return { players, typical };
  }

  return {
    P_AMERICAN,
    P_EUROPEAN,
    STRATEGIES,
    solveExact,
    exactDensity,
    simulateMany,
    simulatePlayer,
    makeRandom,
  };
});
