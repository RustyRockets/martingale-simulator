# Betting strategies.
#
# A strategy is a small state machine that both engines share: the Monte Carlo
# simulator (simulate.R) and the exact solver (exact.R). Using one definition
# for both is what lets the tests check the simulation against exact answers.
#
# Each strategy is a list with:
#   name   display name
#   init   function(unit) -> starting memory (a short numeric vector)
#   stake  function(mem, cash, goal, unit, table_max) -> amount the player
#          wants to bet next, before the "can't bet more than you have" cap
#   update function(mem, won, unit, table_max) -> memory after a spin
#
# All amounts are in dollars. Bets are on an even-money chance (red/black),
# so a win pays the stake and a loss forfeits it.
#
# Table limits: when a progression asks for more than the table maximum, the
# player cannot follow the system any further, accepts the loss, and starts
# over at the base bet. This matches the table-limit model in Pflaumer (2019).

# Shared helper: restart at `reset` if a progression would exceed the limit.
within_limit <- function(next_bet, reset, table_max) {
  if (next_bet > table_max) reset else next_bet
}

# Flat betting: the same base bet every spin. The baseline every system is
# trying to beat.
flat <- function() {
  list(
    name = "Flat bets",
    init = function(unit) numeric(0),
    stake = function(mem, cash, goal, unit, table_max) unit,
    update = function(mem, won, unit, table_max) mem
  )
}

# Martingale: double after every loss, back to the base bet after a win.
# Memory is the size of the next bet.
martingale <- function() {
  list(
    name = "Martingale",
    init = function(unit) unit,
    stake = function(mem, cash, goal, unit, table_max) mem,
    update = function(mem, won, unit, table_max) {
      if (won) unit else within_limit(2 * mem, unit, table_max)
    }
  )
}

# Reverse Martingale: double after every win, back to the base bet after a
# loss. Lets winnings ride instead of chasing losses.
reverse_martingale <- function() {
  list(
    name = "Reverse Martingale",
    init = function(unit) unit,
    stake = function(mem, cash, goal, unit, table_max) mem,
    update = function(mem, won, unit, table_max) {
      if (won) within_limit(2 * mem, unit, table_max) else unit
    }
  )
}

# D'Alembert: add one base unit after a loss, remove one after a win (never
# below the base bet). A gentler progression than doubling.
dalembert <- function() {
  list(
    name = "D'Alembert",
    init = function(unit) unit,
    stake = function(mem, cash, goal, unit, table_max) mem,
    update = function(mem, won, unit, table_max) {
      if (won) max(unit, mem - unit) else within_limit(mem + unit, unit, table_max)
    }
  )
}

# Fibonacci: bets follow 1, 1, 2, 3, 5, 8, ... base units. Step forward one
# term after a loss, back two after a win. Memory is the position in the
# sequence.
fibonacci <- function() {
  fib <- function(k) {
    a <- 1; b <- 1
    if (k <= 2) return(1)
    for (i in 3:k) { s <- a + b; a <- b; b <- s }
    b
  }
  list(
    name = "Fibonacci",
    init = function(unit) 1,
    stake = function(mem, cash, goal, unit, table_max) unit * fib(mem),
    update = function(mem, won, unit, table_max) {
      if (won) return(max(1, mem - 2))
      if (unit * fib(mem + 1) > table_max) 1 else mem + 1
    }
  )
}

# Bold play: bet whatever gets you to the goal in one win, or everything you
# have if that is less. Dubins and Savage (1965) proved this maximises the
# chance of reaching a goal in a game where the odds are against you.
# Without a goal it simply bets everything.
bold_play <- function() {
  list(
    name = "Bold play",
    init = function(unit) numeric(0),
    stake = function(mem, cash, goal, unit, table_max) {
      min(cash, goal - cash, table_max)
    },
    update = function(mem, won, unit, table_max) mem
  )
}

# Every strategy, keyed by a short id. Used by the report and the explorer.
all_strategies <- function() {
  list(
    flat = flat(),
    martingale = martingale(),
    reverse_martingale = reverse_martingale(),
    dalembert = dalembert(),
    fibonacci = fibonacci(),
    bold_play = bold_play()
  )
}

# Win probabilities for a bet on red.
P_AMERICAN <- 18 / 38  # 0 and 00 both lose
P_EUROPEAN <- 18 / 37  # single 0 loses

# The amount actually staked: what the strategy asks for, capped at the cash
# in hand (a player who can't cover the full bet bets what is left).
placed_bet <- function(strategy, mem, cash, goal, unit, table_max) {
  min(strategy$stake(mem, cash, goal, unit, table_max), cash)
}
