# The data behind the shared charts. Drawing itself is checked by eye.

test_that("player states always add up to everyone", {
  set.seed(3)
  sims <- simulate_many(300, martingale(), 100, P_AMERICAN, 5, goal = 200)
  s <- status_over_time(sims$spins, sims$reached_goal, 200)
  totals <- tapply(s$share, s$spin, sum)
  expect_equal(as.numeric(totals), rep(1, 201))
})

test_that("everyone starts out playing and finished players are counted once", {
  spins <- c(1, 2, 3, 10)
  reached <- c(FALSE, TRUE, FALSE, TRUE)
  s <- status_over_time(spins, reached, 10)
  at <- function(t, state) s$share[s$spin == t & s$status == state]
  expect_equal(at(0, "Still playing"), 1)
  expect_equal(at(2, "Went broke"), 0.25)
  expect_equal(at(2, "Reached target"), 0.25)
  expect_equal(at(10, "Still playing"), 0)
  expect_equal(at(10, "Went broke"), 0.5)
})

test_that("density counts every in-range spin exactly once", {
  # 3 spins inside the grid; the 0 and the value at the top edge are excluded
  run <- list(cash = c(50, 150, 250, 0))
  d <- session_density(list(run, run), max_spin = 10, max_cash = 300, nx = 10, ny = 3)
  expect_equal(sum(d$n), 6)
  expect_equal(d$n[d$spin == 0.5 & d$cash == 50], 2)
  expect_equal(d$n[d$spin == 2.5 & d$cash == 250], 2)
})

test_that("density ignores spins beyond the chart", {
  run <- list(cash = rep(100, 50))
  d <- session_density(list(run), max_spin = 10, max_cash = 300, nx = 5, ny = 3)
  expect_equal(sum(d$n), 10)
})

test_that("density leaves out the spin where a winner hits the target", {
  run <- list(cash = c(100, 200, 300), reached_goal = TRUE)
  d <- session_density(list(run), max_spin = 10, max_cash = 400, nx = 10, ny = 4)
  expect_equal(sum(d$n), 2)
})

test_that("the typical run is the one nearest the median on both measures", {
  make <- function(peak, spins) list(peak = peak, spins = spins)
  runs <- list(make(100, 10), make(400, 40), make(1600, 160))
  expect_equal(typical_run(runs)$spins, 40)
})
