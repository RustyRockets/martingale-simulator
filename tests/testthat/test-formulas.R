# Closed-form helpers checked against published values and brute force.

test_that("Martingale round formulas reproduce Pflaumer (2019), Table 1", {
  # European roulette, table limit allowing 10 bets (1 to 512 units).
  r <- martingale_round(n = 10, p = P_EUROPEAN)
  expect_equal(r$exp_gain, -0.30563, tolerance = 1e-4)
  expect_equal(r$exp_spins, 2.05293, tolerance = 1e-5)
  expect_equal(r$exp_bet, 11.30815, tolerance = 1e-5)
  expect_equal(r$exp_bet_per_spin, 5.50829, tolerance = 1e-5)
})

test_that("losing-streak probability matches brute-force enumeration", {
  q <- 20 / 38
  n <- 10
  k <- 3
  # enumerate all 2^10 win/loss sequences
  brute <- 0
  for (code in 0:(2^n - 1)) {
    loss <- as.logical(bitwAnd(code, 2^(0:(n - 1))))
    runs <- rle(loss)
    if (any(runs$values & runs$lengths >= k)) {
      brute <- brute + q^sum(loss) * (1 - q)^sum(!loss)
    }
  }
  expect_equal(prob_losing_streak(k, n, q), brute, tolerance = 1e-12)
})

test_that("losing-streak edge cases", {
  q <- 0.6
  expect_equal(prob_losing_streak(5, 4, q), 0)
  expect_equal(prob_losing_streak(4, 4, q), q^4)
  expect_equal(prob_losing_streak(1, 3, q), 1 - 0.4^3)
})

test_that("a $400 bankroll covers six straight $5 Martingale losses", {
  # 5 + 10 + 20 + 40 + 80 + 160 = 315; the seventh bet (320) exceeds the 85 left
  expect_equal(max_covered_streak(400, 5), 6)
})
