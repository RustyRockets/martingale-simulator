# Exact engine: answers without simulation.
#
# With a finite goal, a session is a Markov chain whose state is
# (cash in hand, the strategy's memory). From each state there are exactly two
# next states, one for a win and one for a loss. This file lists every state
# the player can reach, then solves the chain's linear equations for:
#   p_goal       probability of reaching the goal before going broke
#   exp_wagered  expected total amount bet over the session
#   exp_spins    expected number of spins
#   exp_result   expected profit (negative = loss)
#
# exp_result is computed directly from the final cash, not from the house
# edge, so the tests can check the identity exp_result = (2p - 1) * exp_wagered
# as an independent result rather than assuming it.

solve_exact <- function(strategy, bankroll, p, unit, goal, table_max = Inf,
                        max_states = 3e5) {
  if (!is.finite(goal) || goal <= bankroll) {
    stop("solve_exact needs a finite goal above the bankroll")
  }
  q <- 1 - p

  # State registry: key -> row number, plus the cash and memory of each row.
  index <- new.env(hash = TRUE)
  cash_of <- numeric(0)
  mem_of <- list()
  key <- function(cash, mem) paste(sprintf("%.6f", c(cash, mem)), collapse = "|")
  lookup <- function(cash, mem) {
    k <- key(cash, mem)
    id <- index[[k]]
    if (is.null(id)) {
      id <- length(cash_of) + 1
      if (id > max_states) stop("state space too large; use a smaller bankroll/goal ratio")
      index[[k]] <- id
      cash_of[id] <<- cash
      mem_of[[id]] <<- mem
    }
    id
  }

  # Transition lists, filled as states are discovered (breadth-first).
  from <- integer(0); to <- integer(0); prob <- numeric(0)
  b_goal <- numeric(0)   # one-step probability of landing on the goal
  b_final <- numeric(0)  # one-step expected final cash from absorbing moves
  bet_of <- numeric(0)   # stake placed in each state

  # A move to next_cash either ends the session (broke or goal) or leads to
  # another transient state.
  add_move <- function(i, next_cash, next_mem, pr) {
    if (next_cash >= goal) {
      b_goal[i] <<- b_goal[i] + pr
      b_final[i] <<- b_final[i] + pr * next_cash
    } else if (next_cash > 0) {
      j <- lookup(next_cash, next_mem)
      from[length(from) + 1] <<- i
      to[length(to) + 1] <<- j
      prob[length(prob) + 1] <<- pr
    }
    # next_cash <= 0: broke, contributes nothing (final cash is 0)
  }

  lookup(bankroll, strategy$init(unit))
  i <- 0
  while (i < length(cash_of)) {
    i <- i + 1
    cash <- cash_of[i]
    mem <- mem_of[[i]]
    bet <- placed_bet(strategy, mem, cash, goal, unit, table_max)
    bet_of[i] <- bet
    b_goal[i] <- 0
    b_final[i] <- 0
    add_move(i, cash + bet, strategy$update(mem, TRUE, unit, table_max), p)
    add_move(i, cash - bet, strategy$update(mem, FALSE, unit, table_max), q)
  }

  # Each quantity v satisfies v = Q v + b, so solve (I - Q) v = b for all four
  # right-hand sides at once. Q is sparse (two entries per row at most).
  n <- length(cash_of)
  Q <- Matrix::sparseMatrix(i = from, j = to, x = prob, dims = c(n, n))
  A <- Matrix::Diagonal(n) - Q
  B <- cbind(b_goal, bet_of, rep(1, n), b_final)
  X <- unname(as.matrix(Matrix::solve(A, B)))

  list(
    p_goal = X[1, 1],
    exp_wagered = X[1, 2],
    exp_spins = X[1, 3],
    exp_result = X[1, 4] - bankroll,
    n_states = n
  )
}

# Convenience: exact results for several strategies as one data frame.
compare_exact <- function(strategies, bankroll, p, unit, goal, table_max = Inf) {
  rows <- lapply(strategies, function(s) {
    r <- solve_exact(s, bankroll, p, unit, goal, table_max)
    data.frame(strategy = s$name, p_goal = r$p_goal, exp_result = r$exp_result,
               exp_wagered = r$exp_wagered, exp_spins = r$exp_spins)
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
