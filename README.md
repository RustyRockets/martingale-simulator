# Can a betting system beat the house?

The **Martingale** betting system (double your bet after every loss) has tempted gamblers
since at least Casanova, and it does win most of the time. This project shows why it still
loses, what works better if you must gamble, and why a high win rate can mislead.

It compares six roulette strategies in R using two independent engines, a Monte Carlo
simulator and an exact Markov-chain solver, tested against each other and against
published results.

**[Read the analysis](https://rustyrockets.github.io/martingale-simulator/)** ·
**[Try the explorer](https://rustyrockets.github.io/martingale-simulator/explorer/)**
(runs R in the browser)

![Chance of doubling $400 before going broke, by strategy](images/strategy_comparison.png)

## Findings

Scenario: American roulette, betting red, $5 base bet, $400 bankroll, trying to reach $800.

- **A betting system can't change the house edge.** The average result is −5.26% (the
  edge) × the total amount bet. This is a known result, and the exact solver confirms it
  for all six strategies. The Martingale bets $2,226 on average to chase a $400 profit.
- **One bold bet beats the Martingale.** A single $400 bet on red doubles your money
  47.4% of the time, against 35.4% for the Martingale, and costs less on average ($21
  vs $117). Dubins and Savage (1965) proved that bold play is optimal for reaching a
  goal in an unfavorable game.
- **A high win rate is misleading.** Aiming for a $25 profit, the Martingale succeeds
  91% of the time and still loses $12 on average, because the other 9% of sessions lose
  the whole $400. The same payoff shape appears in doubling strategies outside the casino.

![Martingale results with a $25 target: 91.4% of sessions win $25, 8.6% lose $400](images/win_rate.png)

## Usage

```r
for (f in list.files("R", full.names = TRUE)) source(f)

# Exact answer: chance a Martingale player turns $400 into $800
solve_exact(martingale(), bankroll = 400, p = P_AMERICAN, unit = 5, goal = 800)

# The same question by simulation
sims <- simulate_many(10000, martingale(), 400, P_AMERICAN, 5, goal = 800)
mean(sims$reached_goal)

# Compare every strategy at once
compare_exact(all_strategies(), 400, P_AMERICAN, 5, goal = 800)
```

Strategies: `flat()`, `martingale()`, `reverse_martingale()`, `dalembert()`,
`fibonacci()`, `bold_play()`. Each simulator and solver call also takes a
`table_max` (table limit).

Build everything (tests, report, explorer) into `docs/`:

```bash
Rscript build_site.R
```

Built with R 4.4 and [Quarto](https://quarto.org), and the packages ggplot2, dplyr,
patchwork, scales, knitr, rmarkdown, testthat, Matrix, shiny, bslib and
shinylive. Run the tests alone with `Rscript -e 'testthat::test_dir("tests/testthat")'`.

## Structure

| Path | Purpose |
|---|---|
| `R/strategies.R` | Betting strategies as small state machines, shared by both engines |
| `R/simulate.R` | Monte Carlo engine: plays sessions spin by spin |
| `R/exact.R` | Exact engine: solves each session as a Markov chain |
| `R/formulas.R` | Closed-form results from the literature, used to check the engines |
| `tests/testthat/` | Engine vs engine vs published formulas |
| `report/` | Quarto source for the write-up |
| `explorer/app.R` | Shiny app, exported with Shinylive to run in the browser |
| `build_site.R` | Runs the tests and builds the site |
| `.github/workflows/deploy.yml` | Builds and publishes to GitHub Pages on push to `main` |

## License

[MIT](LICENSE)
