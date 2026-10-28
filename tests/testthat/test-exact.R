# The exact solver checked against closed-form results it does not use.

test_that("flat betting matches the gambler's ruin formula", {
  for (p in c(P_AMERICAN, P_EUROPEAN, 0.5)) {
    for (cfg in list(c(10, 20), c(30, 50), c(80, 160))) {
      r <- solve_exact(flat(), bankroll = cfg[1], p = p, unit = 1, goal = cfg[2])
      expect_equal(r$p_goal, gamblers_ruin(cfg[1], cfg[2], p), tolerance = 1e-10)
    }
  }
})

test_that("bold play matches the Dubins-Savage recursion", {
  for (p in c(P_AMERICAN, P_EUROPEAN)) {
    for (bankroll in c(100, 300, 400, 500, 700)) {
      r <- solve_exact(bold_play(), bankroll = bankroll, p = p, unit = 5, goal = 800)
      expect_equal(r$p_goal, bold_play_prob(bankroll / 800, p), tolerance = 1e-10)
    }
  }
})

test_that("doubling $400 to $800 with one bet succeeds with probability p", {
  r <- solve_exact(bold_play(), 400, P_AMERICAN, 5, 800)
  expect_equal(r$p_goal, 18 / 38)
  expect_equal(r$exp_spins, 1)
})

test_that("expected result = (2p - 1) x expected amount wagered, for every strategy", {
  # The solver computes the expected result from final cash, so this is an
  # independent check of the identity, not a restatement of it.
  for (p in c(P_AMERICAN, P_EUROPEAN)) {
    for (tmax in c(Inf, 100)) {
      for (s in all_strategies()) {
        r <- solve_exact(s, bankroll = 200, p = p, unit = 5, goal = 400, table_max = tmax)
        expect_equal(r$exp_result, (2 * p - 1) * r$exp_wagered, tolerance = 1e-8,
                     label = paste(s$name, p, tmax))
      }
    }
  }
})

test_that("a fair game gives every strategy an expected result of zero", {
  for (s in all_strategies()) {
    r <- solve_exact(s, bankroll = 100, p = 0.5, unit = 5, goal = 200)
    expect_equal(r$exp_result, 0, tolerance = 1e-8, label = s$name)
  }
})

test_that("the headline Martingale number matches an independent calculation", {
  # 0.35357 was first computed with a separate Python value-iteration script.
  r <- solve_exact(martingale(), 400, P_AMERICAN, 5, 800)
  expect_equal(r$p_goal, 0.35357, tolerance = 1e-4)
})

test_that("the solver rejects an infinite goal", {
  expect_error(solve_exact(martingale(), 400, P_AMERICAN, 5, Inf))
})
