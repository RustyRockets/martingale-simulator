# The Monte Carlo engine checked against the exact solver and published
# formulas. Seeds are fixed; tolerances are several standard errors wide so
# the tests check agreement rather than luck.

test_that("simulated success rates and results agree with the exact solver", {
  set.seed(42)
  n <- 4000
  for (s in all_strategies()) {
    exact <- solve_exact(s, bankroll = 100, p = P_AMERICAN, unit = 5, goal = 200)
    sim <- simulate_many(n, s, bankroll = 100, p = P_AMERICAN, unit = 5, goal = 200)

    se_p <- sqrt(exact$p_goal * (1 - exact$p_goal) / n)
    expect_lt(abs(mean(sim$reached_goal) - exact$p_goal), 4 * se_p + 1e-9,
              label = paste(s$name, "success rate"))

    se_r <- sd(sim$result) / sqrt(n)
    expect_lt(abs(mean(sim$result) - exact$exp_result), 4 * se_r + 1e-9,
              label = paste(s$name, "mean result"))
  }
})

test_that("with a table limit, the average bet per spin matches Pflaumer", {
  # Effectively unlimited bankroll, European wheel, 1-unit base bet, 512 max.
  set.seed(7)
  r <- simulate_player(martingale(), bankroll = 1e9, p = P_EUROPEAN, unit = 1,
                       table_max = 512, max_spins = 4e5)
  expect_equal(r$wagered / r$spins, martingale_round(10, P_EUROPEAN)$exp_bet_per_spin,
               tolerance = 0.04)
})

test_that("a session stops at the goal, at ruin, or at max_spins", {
  set.seed(1)
  r <- simulate_player(martingale(), 400, P_AMERICAN, 5, goal = 800, path = TRUE)
  expect_true(r$final <= 0 || r$final >= 800)
  expect_equal(length(r$cash), r$spins)
  expect_equal(sum(r$stakes), r$wagered)

  r2 <- simulate_player(flat(), 400, P_AMERICAN, 5, max_spins = 10)
  expect_equal(r2$spins, 10)
})
