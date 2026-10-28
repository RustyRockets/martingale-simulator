# Monte Carlo engine: play one gambler spin by spin, or many gamblers at once.
#
# A session ends when the player is broke, reaches the goal, or has played
# max_spins spins. Leaving goal = Inf means "play until broke", which is how
# the original version of this project ran every session.

# Simulate one player.
#   strategy   a strategy from strategies.R
#   bankroll   starting cash
#   p          probability of winning one even-money bet
#   unit       base bet
#   goal       walk away once cash reaches this amount (Inf = never)
#   table_max  largest bet the table accepts (Inf = no limit)
#   max_spins  safety stop for very long sessions
#   path       keep the spin-by-spin record (needed for plots, slower)
#
# Returns a list: spins, final cash, peak cash, total wagered, whether the
# goal was reached, and (if path = TRUE) per-spin stakes, outcomes and cash.
simulate_player <- function(strategy, bankroll, p, unit, goal = Inf,
                            table_max = Inf, max_spins = 1e6, path = FALSE) {
  cash <- bankroll
  peak <- bankroll
  wagered <- 0
  spins <- 0
  mem <- strategy$init(unit)

  if (path) {
    stakes <- numeric(0); outcomes <- logical(0); cash_path <- numeric(0)
  }

  # Draw random numbers in batches: much faster than one runif() per spin.
  batch <- 1024
  draws <- runif(batch)
  k <- 0

  while (cash > 0 && cash < goal && spins < max_spins) {
    bet <- placed_bet(strategy, mem, cash, goal, unit, table_max)
    k <- k + 1
    if (k > batch) { draws <- runif(batch); k <- 1 }
    won <- draws[k] < p

    cash <- cash + if (won) bet else -bet
    wagered <- wagered + bet
    spins <- spins + 1
    peak <- max(peak, cash)
    mem <- strategy$update(mem, won, unit, table_max)

    if (path) {
      stakes[spins] <- bet; outcomes[spins] <- won; cash_path[spins] <- cash
    }
  }

  out <- list(spins = spins, final = cash, peak = peak, wagered = wagered,
              reached_goal = cash >= goal)
  if (path) {
    out$stakes <- stakes
    out$won <- outcomes
    out$cash <- cash_path
  }
  out
}

# Simulate n independent players with the same settings. Returns a data frame
# with one row per player (no spin-by-spin paths).
simulate_many <- function(n, strategy, bankroll, p, unit, goal = Inf,
                          table_max = Inf, max_spins = 1e6) {
  rows <- lapply(seq_len(n), function(i) {
    r <- simulate_player(strategy, bankroll, p, unit, goal, table_max, max_spins)
    c(spins = r$spins, final = r$final, peak = r$peak,
      wagered = r$wagered, reached_goal = r$reached_goal)
  })
  df <- as.data.frame(do.call(rbind, rows))
  df$reached_goal <- as.logical(df$reached_goal)
  df$result <- df$final - bankroll
  df
}
