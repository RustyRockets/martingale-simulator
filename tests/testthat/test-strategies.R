# Each strategy's bet-sizing rule, step by step.

# Feed a strategy a sequence of outcomes and record the stake before each spin.
stakes_for <- function(strategy, outcomes, unit = 1, table_max = Inf,
                       cash = 1e6, goal = Inf) {
  mem <- strategy$init(unit)
  out <- numeric(0)
  for (won in outcomes) {
    out <- c(out, strategy$stake(mem, cash, goal, unit, table_max))
    mem <- strategy$update(mem, won, unit, table_max)
  }
  out
}

test_that("Martingale doubles after losses and resets after a win", {
  expect_equal(stakes_for(martingale(), c(FALSE, FALSE, FALSE, TRUE, FALSE)),
               c(1, 2, 4, 8, 1))
})

test_that("Martingale restarts at the base bet when the table limit is hit", {
  # limit 4: bets 1, 2, 4, then 8 is not allowed, so back to 1
  expect_equal(stakes_for(martingale(), rep(FALSE, 5), table_max = 4),
               c(1, 2, 4, 1, 2))
})

test_that("Reverse Martingale doubles after wins", {
  expect_equal(stakes_for(reverse_martingale(), c(TRUE, TRUE, FALSE, TRUE)),
               c(1, 2, 4, 1))
})

test_that("D'Alembert moves one unit at a time and never drops below base", {
  expect_equal(stakes_for(dalembert(), c(FALSE, FALSE, TRUE, TRUE, TRUE)),
               c(1, 2, 3, 2, 1))
})

test_that("Fibonacci walks the sequence: forward one on loss, back two on win", {
  expect_equal(stakes_for(fibonacci(), c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE)),
               c(1, 1, 2, 3, 5, 2))
})

test_that("Bold play bets exactly what is needed, or everything", {
  s <- bold_play()
  expect_equal(s$stake(numeric(0), cash = 300, goal = 800, unit = 5, table_max = Inf), 300)
  expect_equal(s$stake(numeric(0), cash = 600, goal = 800, unit = 5, table_max = Inf), 200)
  expect_equal(s$stake(numeric(0), cash = 600, goal = Inf, unit = 5, table_max = Inf), 600)
})

test_that("a player who can't cover the bet stakes what is left", {
  expect_equal(placed_bet(martingale(), mem = 320, cash = 85, goal = Inf,
                          unit = 5, table_max = Inf), 85)
})
