// Checks the explorer's JavaScript engine against the R engine and against itself.
// Run from the repository root, after explorer/tests/make_reference.R:
//   node --test explorer/tests/engine.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const Engine = require("../engine.js");

const reference = JSON.parse(fs.readFileSync("explorer/tests/reference.json", "utf8"));
const close = (a, b, tolerance, label) =>
  assert.ok(Math.abs(a - b) <= tolerance, `${label}: ${a} vs ${b}`);

test("every exact result matches the R engine", () => {
  assert.ok(reference.length >= 36);
  for (const r of reference) {
    const p = r.wheel === "american" ? Engine.P_AMERICAN : Engine.P_EUROPEAN;
    const js = Engine.solveExact(Engine.STRATEGIES[r.strategy], r.bankroll, p, r.unit, r.goal, r.tableMax ?? Infinity);
    const label = `${r.strategy} ${r.bankroll}->${r.goal} max ${r.tableMax} ${r.wheel}`;
    close(js.pGoal, r.pGoal, 1e-9, `${label} pGoal`);
    close(js.expResult, r.expResult, 1e-6, `${label} expResult`);
    close(js.expWagered, r.expWagered, 1e-6, `${label} expWagered`);
    close(js.expSpins, r.expSpins, 1e-6, `${label} expSpins`);
  }
});

test("the average loss is the house edge times the amount bet", () => {
  for (const s of Object.values(Engine.STRATEGIES)) {
    const r = Engine.solveExact(s, 400, Engine.P_AMERICAN, 5, 800);
    close(r.expResult, (2 * Engine.P_AMERICAN - 1) * r.expWagered, 1e-6, s.name);
  }
});

test("won, broke and still-playing shares add up at every spin", () => {
  const { status } = Engine.solveExact(Engine.STRATEGIES.martingale, 400, Engine.P_AMERICAN, 5, 800);
  status.won.forEach((won, t) => {
    const playing = 1 - won - status.broke[t];
    assert.ok(playing >= -1e-12 && playing <= 1 + 1e-12);
    if (t > 0) assert.ok(won >= status.won[t - 1] && status.broke[t] >= status.broke[t - 1]);
  });
});

test("the heat map holds exactly the players still at the table", () => {
  const p = Engine.P_AMERICAN;
  const r = Engine.solveExact(Engine.STRATEGIES.martingale, 400, p, 5, 800);
  const maxSpin = 200;
  const d = Engine.exactDensity(r.chain, p, maxSpin, 800, 200, 20);
  // One column per spin, so each column should total the share still playing
  for (const spin of [1, 50, 120, 200]) {
    let total = 0;
    for (let y = 0; y < d.ny; y++) total += d.cells[y * d.nx + spin - 1];
    close(total, 1 - r.status.won[spin] - r.status.broke[spin], 1e-9, `spin ${spin}`);
  }
});

test("simulation agrees with the exact results for every strategy", () => {
  const n = 20000;
  for (const [id, s] of Object.entries(Engine.STRATEGIES)) {
    const exact = Engine.solveExact(s, 100, Engine.P_AMERICAN, 5, 200);
    const { players } = Engine.simulateMany(n, s, 100, Engine.P_AMERICAN, 5, 200, Infinity, 1000);
    const share = players.filter((x) => x.reachedGoal).length / n;
    const se = Math.sqrt((exact.pGoal * (1 - exact.pGoal)) / n);
    close(share, exact.pGoal, 4 * se + 1e-9, id);
  }
});

test("one bold bet doubles with probability p, in one spin", () => {
  const r = Engine.solveExact(Engine.STRATEGIES.bold_play, 400, Engine.P_AMERICAN, 5, 800);
  close(r.pGoal, 18 / 38, 1e-12, "pGoal");
  close(r.expSpins, 1, 1e-12, "expSpins");
});

test("the largest allowed settings stay fast", () => {
  const started = Date.now();
  for (const s of Object.values(Engine.STRATEGIES)) {
    const r = Engine.solveExact(s, 1000, Engine.P_AMERICAN, 5, 2000);
    Engine.exactDensity(r.chain, Engine.P_AMERICAN, 500, 2000, 120, 30);
  }
  const elapsed = Date.now() - started;
  console.log(`all six strategies at the size limit: ${elapsed} ms`);
  assert.ok(elapsed < 15000);
});
