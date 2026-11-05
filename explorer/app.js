// The explorer's page logic: read the settings, run engine.js, draw the results.
// Charts are drawn by hand with canvas and SVG so the page needs no libraries.

(function () {
  const $ = (id) => document.getElementById(id);

  // Size limits keep every update well under a second. The heaviest strategy's
  // state count grows with (goal / base bet)^2.
  const MAX_BANKROLL_UNITS = 200;
  const MAX_GOAL_UNITS = 400;

  const INK = "#1c1d1f";
  const MUTED = "#5d6066";
  const COLORS = { won: "#1baf7a", playing: "#d9dde2", broke: "#5d6066" };
  const HEAT_STOPS = [[255, 255, 255], [214, 230, 248], [127, 176, 230], [42, 120, 214], [13, 59, 122]];
  const MARGIN = { top: 8, right: 14, bottom: 34, left: 50 };

  let current = null; // results of the latest update, for redraws and hover

  const percent = (x, digits = 1) => `${(100 * x).toFixed(digits)}%`;
  // A probability for display: an extra digit near 0% and 100%, so a small chance
  // doesn't round to a flat 0.0% or a near-certainty to 100.0%
  const chance = (x) => {
    if (x > 0 && x < 0.0001) return "<0.01%";
    if (x < 1 && x > 0.9999) return ">99.99%";
    return percent(x, x < 0.01 || x > 0.99 ? 2 : 1);
  };
  const whole = (x) => Math.round(x).toLocaleString("en-US");
  const dollars = (x) => `${x < 0 ? "−" : ""}$${whole(Math.abs(x))}`;

  // About five round-numbered axis ticks between 0 and max
  function ticks(max, target = 5) {
    const raw = max / target;
    const size = 10 ** Math.floor(Math.log10(raw));
    const step = [1, 2, 2.5, 5, 10].map((m) => m * size).find((s) => s >= raw);
    const out = [];
    for (let v = 0; v <= max + 1e-9; v += step) out.push(v);
    return out;
  }

  function readSettings() {
    const bankroll = Number($("bankroll").value);
    const target = Number($("target").value);
    const unit = Number($("unit").value);
    const wheel = document.querySelector('input[name="wheel"]:checked').value;
    let problem = null;
    if (!Number.isInteger(bankroll) || !Number.isInteger(target) || bankroll < unit || target <= 0) {
      problem = "Use whole dollars, with a bankroll of at least one base bet and a positive target.";
    } else if (bankroll / unit > MAX_BANKROLL_UNITS || (bankroll + target) / unit > MAX_GOAL_UNITS) {
      problem = `Keep the bankroll within ${MAX_BANKROLL_UNITS} base bets, and bankroll plus target within ${MAX_GOAL_UNITS}.`;
    }
    return {
      strategy: Engine.STRATEGIES[$("strategy").value],
      p: wheel === "american" ? Engine.P_AMERICAN : Engine.P_EUROPEAN,
      bankroll,
      goal: bankroll + target,
      unit,
      tableMax: Number($("tableMax").value),
      players: Number($("players").value),
      problem,
    };
  }

  function update() {
    const s = readSettings();
    $("problem").hidden = !s.problem;
    $("problem").textContent = s.problem || "";
    if (s.problem) return;

    const exact = Engine.solveExact(s.strategy, s.bankroll, s.p, s.unit, s.goal, s.tableMax);

    // Chart up to the spin where 95% of sessions have ended
    const { won, broke } = exact.status;
    let maxSpin = won.findIndex((w, t) => w + broke[t] >= 0.95);
    if (maxSpin < 0) maxSpin = won.length - 1;
    maxSpin = Math.max(5, maxSpin);

    // About 70 cash rows, each a whole number of base bets
    const band = s.unit * Math.ceil(s.goal / s.unit / 70);
    const density = Engine.exactDensity(exact.chain, s.p, maxSpin, s.goal, 120, band);
    const sim = Engine.simulateMany(s.players, s.strategy, s.bankroll, s.p, s.unit, s.goal, s.tableMax);
    current = { s, exact, density, sim, maxSpin };

    $("pGoal").textContent = chance(exact.pGoal);
    $("expResult").textContent = dollars(exact.expResult);
    $("expWagered").textContent = dollars(exact.expWagered);
    $("expSpins").textContent = whole(exact.expSpins);
    drawLegend();
    drawNotes();
    drawCharts();
  }

  function drawLegend() {
    const { exact } = current;
    const items = [["Reached target", COLORS.won, exact.pGoal], ["Went broke", COLORS.broke, 1 - exact.pGoal]];
    $("legend").innerHTML =
      items.map(([label, color, share]) => `<span><i style="background:${color}"></i>${label} ${chance(share)}</span>`).join("") +
      `<span><i style="background:${COLORS.playing}"></i>Still playing</span>`;
  }

  // Simulated results with 95% margins of error, so sampling noise isn't
  // mistaken for a disagreement with the exact numbers
  function drawNotes() {
    const { exact, sim, maxSpin } = current;
    const n = sim.players.length;
    const results = sim.players.map((x) => x.final - current.s.bankroll);
    const share = sim.players.filter((x) => x.reachedGoal).length / n;
    const mean = results.reduce((a, b) => a + b, 0) / n;
    const sd = Math.sqrt(results.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1));
    $("heatNote").textContent = `Darker means more players held that amount. The black line is a typical session. Showing the first ${whole(maxSpin)} spins, when 95% of sessions had ended.`;
    $("simNote").textContent = `Check: ${whole(n)} simulated players reached the target ${percent(share)} of the time (±${(196 * Math.sqrt((share * (1 - share)) / n)).toFixed(1)}), averaging ${dollars(mean)} (±$${whole((1.96 * sd) / Math.sqrt(n))}). Exact: ${chance(exact.pGoal)}, ${dollars(exact.expResult)}.`;
  }

  function plotArea(el) {
    const width = el.clientWidth;
    const height = el.clientHeight;
    return {
      width,
      height,
      x0: MARGIN.left,
      y0: MARGIN.top,
      w: width - MARGIN.left - MARGIN.right,
      h: height - MARGIN.top - MARGIN.bottom,
    };
  }

  function axes(a, maxX, maxY, yLabel) {
    const x = (v) => a.x0 + (v / maxX) * a.w;
    const y = (v) => a.y0 + a.h - (v / maxY) * a.h;
    const xs = ticks(maxX, a.w < 300 ? 4 : 6).map((v) =>
      `<text x="${x(v)}" y="${a.y0 + a.h + 16}" text-anchor="middle" fill="${MUTED}">${whole(v)}</text>`);
    const ys = ticks(maxY, 4).map((v) =>
      `<text x="${a.x0 - 6}" y="${y(v) + 4}" text-anchor="end" fill="${MUTED}">${yLabel(v)}</text>`);
    const title = `<text x="${a.x0 + a.w / 2}" y="${a.height - 2}" text-anchor="middle" fill="${INK}">Spin</text>`;
    return xs.join("") + ys.join("") + title;
  }

  function heatColor(t) {
    const pos = Math.min(Math.max(t, 0), 1) * (HEAT_STOPS.length - 1);
    const i = Math.min(Math.floor(pos), HEAT_STOPS.length - 2);
    return HEAT_STOPS[i].map((c, k) => c + (HEAT_STOPS[i + 1][k] - c) * (pos - i));
  }

  function drawHeat() {
    const el = $("heat");
    const { s, density, sim, maxSpin } = current;
    const { cells, nx, ny } = density;

    // Sessions can end too quickly to leave anything to draw
    const values = Array.from(cells).filter((v) => v > 0).sort((a, b) => a - b);
    if (!values.length) {
      el.innerHTML = '<div class="empty">Every session ended too quickly to chart. See how they ended alongside.</div>';
      el.setAttribute("aria-label", "No heat map: every session ended too quickly to chart.");
      return;
    }

    // Shade on a cube-root scale, capped so the crowded first spins don't wash
    // out the rest: fainter bands stay visible, and the ridge fades as players leave
    const top = values[Math.floor(values.length * 0.995)] || values[values.length - 1];
    const small = document.createElement("canvas");
    small.width = nx;
    small.height = ny;
    const ctx = small.getContext("2d");
    const image = ctx.createImageData(nx, ny);
    for (let row = 0; row < ny; row++) {
      for (let col = 0; col < nx; col++) {
        const [r, g, b] = heatColor(Math.cbrt(cells[row * nx + col] / top));
        const at = ((ny - 1 - row) * nx + col) * 4; // canvas rows run top-down
        image.data.set([r, g, b, 255], at);
      }
    }
    ctx.putImageData(image, 0, 0);

    const a = plotArea(el);
    const ratio = window.devicePixelRatio || 1;
    const canvas = document.createElement("canvas");
    canvas.width = a.width * ratio;
    canvas.height = a.height * ratio;
    canvas.style.width = `${a.width}px`;
    canvas.style.height = `${a.height}px`;
    const big = canvas.getContext("2d");
    big.scale(ratio, ratio);
    big.imageSmoothingEnabled = true;
    big.imageSmoothingQuality = "high";
    big.drawImage(small, a.x0, a.y0, a.w, a.h);

    const x = (v) => a.x0 + (v / maxSpin) * a.w;
    const y = (v) => a.y0 + a.h - (v / density.top) * a.h;
    const path = sim.typical.path
      .slice(0, maxSpin + 1)
      .map((cash, t) => `${x(t).toFixed(1)},${y(Math.min(cash, s.goal)).toFixed(1)}`)
      .join(" ");
    const reference = (value, label) =>
      `<line x1="${a.x0}" x2="${a.x0 + a.w}" y1="${y(value)}" y2="${y(value)}" stroke="${MUTED}" stroke-dasharray="4 4"/>` +
      `<text x="${a.x0 + a.w - 2}" y="${y(value) + 14}" text-anchor="end" fill="${INK}">${label}</text>`;

    el.innerHTML = "";
    el.appendChild(canvas);
    el.insertAdjacentHTML("beforeend", `<svg width="${a.width}" height="${a.height}" aria-hidden="true">
      ${axes(a, maxSpin, density.top, (v) => `$${whole(v)}`)}
      ${reference(s.bankroll, "Start")}${reference(s.goal, "Target")}
      <polyline points="${path}" fill="none" stroke="${INK}" stroke-width="1.3" stroke-linejoin="round"/>
    </svg>`);
    el.setAttribute("aria-label", `Heat map of cash by spin for ${s.strategy.name}, from ${dollars(s.bankroll)} toward ${dollars(s.goal)}.`);
    current.heatArea = a;
  }

  function drawStatus() {
    const el = $("status");
    const { exact, maxSpin } = current;
    const a = plotArea(el);
    const x = (t) => a.x0 + (t / maxSpin) * a.w;
    const y = (share) => a.y0 + a.h - share * a.h;
    const { won, broke } = exact.status;
    const at = (series, t) => series[Math.min(t, series.length - 1)];

    // Around 300 points is smooth at this size however long the sessions run
    const step = Math.max(1, Math.floor(maxSpin / 300));
    const spins = [];
    for (let t = 0; t <= maxSpin; t += step) spins.push(t);
    if (spins[spins.length - 1] !== maxSpin) spins.push(maxSpin);

    const area = (lower, upper, color) => {
      const top = spins.map((t) => `${x(t).toFixed(1)},${y(upper(t)).toFixed(1)}`);
      const bottom = spins.slice().reverse().map((t) => `${x(t).toFixed(1)},${y(lower(t)).toFixed(1)}`);
      return `<polygon points="${top.concat(bottom).join(" ")}" fill="${color}" stroke="#fff" stroke-width="0.8"/>`;
    };
    const brokeAt = (t) => at(broke, t);
    const notWonAt = (t) => 1 - at(won, t);

    el.innerHTML = `<svg width="${a.width}" height="${a.height}" aria-hidden="true">
      ${area(() => 0, brokeAt, COLORS.broke)}
      ${area(brokeAt, notWonAt, COLORS.playing)}
      ${area(notWonAt, () => 1, COLORS.won)}
      ${axes(a, maxSpin, 1, (v) => `${Math.round(100 * v)}%`)}
      <line id="crosshair" y1="${a.y0}" y2="${a.y0 + a.h}" stroke="${INK}" visibility="hidden"/>
    </svg>`;
    el.setAttribute("aria-label", `Stacked area chart of players over time. ${chance(exact.pGoal)} reach the target and the rest go broke.`);
    current.statusArea = a;
  }

  function drawCharts() {
    if (!current) return;
    drawHeat();
    drawStatus();
  }

  // Hover and touch: show the exact values under the pointer
  function showTooltip(event, html) {
    const tip = $("tooltip");
    tip.innerHTML = html;
    tip.hidden = false;
    const left = Math.min(event.clientX + 12, window.innerWidth - tip.offsetWidth - 6);
    tip.style.left = `${Math.max(6, left)}px`;
    tip.style.top = `${Math.max(6, event.clientY - tip.offsetHeight - 10)}px`;
  }

  function hideTooltip() {
    $("tooltip").hidden = true;
    const line = document.getElementById("crosshair");
    if (line) line.setAttribute("visibility", "hidden");
  }

  function pointerIn(el, area, event) {
    const box = el.getBoundingClientRect();
    const fx = (event.clientX - box.left - area.x0) / area.w;
    const fy = 1 - (event.clientY - box.top - area.y0) / area.h;
    return fx >= 0 && fx <= 1 && fy >= 0 && fy <= 1 ? { fx, fy } : null;
  }

  $("heat").addEventListener("pointermove", (event) => {
    if (!current || !current.heatArea) return;
    const hit = pointerIn($("heat"), current.heatArea, event);
    if (!hit) return hideTooltip();
    const { nx, ny, cells, band } = current.density;
    const col = Math.min(Math.floor(hit.fx * nx), nx - 1);
    const row = Math.min(Math.floor(hit.fy * ny), ny - 1);
    showTooltip(event, `Spin ${whole(hit.fx * current.maxSpin)}<br>${dollars(row * band)}–${dollars((row + 1) * band)}: ${percent(cells[row * nx + col], 2)} of players`);
  });

  $("status").addEventListener("pointermove", (event) => {
    if (!current || !current.statusArea) return;
    const a = current.statusArea;
    const hit = pointerIn($("status"), a, event);
    if (!hit) return hideTooltip();
    const { won, broke } = current.exact.status;
    const t = Math.round(hit.fx * current.maxSpin);
    const i = Math.min(t, won.length - 1);
    const line = document.getElementById("crosshair");
    const px = a.x0 + (t / current.maxSpin) * a.w;
    line.setAttribute("x1", px);
    line.setAttribute("x2", px);
    line.setAttribute("visibility", "visible");
    showTooltip(event, `Spin ${whole(t)}<br>Reached target ${percent(won[i])}<br>Still playing ${percent(1 - won[i] - broke[i])}<br>Went broke ${percent(broke[i])}`);
  });

  ["heat", "status"].forEach((id) => $(id).addEventListener("pointerleave", hideTooltip));

  // Tell the report how tall this page is, so its embed needs no inner scrolling
  function reportHeight() {
    if (window.parent !== window) {
      // The body's own height, because the document's can't shrink below the frame
      window.parent.postMessage({ explorerHeight: document.body.offsetHeight }, window.location.origin);
    }
  }

  $("strategy").innerHTML = Object.entries(Engine.STRATEGIES)
    .map(([id, s]) => `<option value="${id}">${s.name}</option>`)
    .join("");
  $("strategy").value = "martingale";

  let pending = null;
  $("controls").addEventListener("input", () => {
    clearTimeout(pending);
    pending = setTimeout(update, 120);
  });
  $("controls").addEventListener("submit", (event) => event.preventDefault());

  new ResizeObserver(() => {
    drawCharts();
    reportHeight();
  }).observe(document.body);

  update();

  // The old R-based explorer installed a service worker. Remove it for returning
  // visitors so it can't serve stale files.
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.getRegistrations().then((all) => all.forEach((sw) => sw.unregister()));
  }
})();
