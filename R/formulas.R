# Closed-form results from the literature. These are independent of both
# engines, so the tests use them to check the simulator and the exact solver.

# Gambler's ruin with flat bets: probability of reaching n units before 0,
# starting from i units, winning each one-unit bet with probability p.
gamblers_ruin <- function(i, n, p) {
  if (p == 0.5) return(i / n)
  r <- (1 - p) / p
  (1 - r^i) / (1 - r^n)
}

# Bold play (Dubins and Savage, 1965): probability of reaching the goal when
# holding fraction x of it. Uses the recursion
#   Q(x) = p * Q(2x)                  for x < 1/2
#   Q(x) = p + (1 - p) * Q(2x - 1)    for x >= 1/2
# which is exact for fractions with a power-of-two denominator and converges
# quickly otherwise.
bold_play_prob <- function(x, p, depth = 60) {
  if (x <= 0) return(0)
  if (x >= 1) return(1)
  if (depth == 0) return(x)  # truncation; contributes < p^60
  if (x < 0.5) p * bold_play_prob(2 * x, p, depth - 1)
  else p + (1 - p) * bold_play_prob(2 * x - 1, p, depth - 1)
}

# One Martingale round with a table limit allowing n bets (Pflaumer, 2019):
# the round ends at the first win (+1 unit) or after n straight losses
# (-(2^n - 1) units). With q = probability of losing a bet:
#   expected gain           1 - (2q)^n
#   expected spins          (1 - q^n) / (1 - q)
#   expected amount bet     (1 - (2q)^n) / (1 - 2q)
#   expected bet per spin   the ratio of the last two
martingale_round <- function(n, p) {
  q <- 1 - p
  exp_bet <- if (q == 0.5) n else (1 - (2 * q)^n) / (1 - 2 * q)
  exp_spins <- (1 - q^n) / (1 - q)
  list(
    exp_gain = 1 - (2 * q)^n,
    exp_spins = exp_spins,
    exp_bet = exp_bet,
    exp_bet_per_spin = exp_bet / exp_spins,
    p_bust = q^n
  )
}

# Longest losing streak a Martingale player can fully cover: the largest L
# with unit * (2^L - 1) <= bankroll. One more loss means the next doubled bet
# is more than the player has left.
max_covered_streak <- function(bankroll, unit) {
  floor(log2(bankroll / unit + 1))
}

# Probability of at least one run of k or more losses in n spins, where each
# spin loses with probability q. Exact, by tracking the length of the current
# losing run (states 0..k-1) and an absorbing "has happened" state.
prob_losing_streak <- function(k, n, q) {
  if (k == 1) return(1 - (1 - q)^n)
  state <- c(1, rep(0, k - 1))  # P(current run length = 0..k-1)
  hit <- 0
  for (s in seq_len(n)) {
    new <- numeric(k)
    new[1] <- sum(state) * (1 - q)          # a win resets the run
    new[2:k] <- state[1:(k - 1)] * q        # a loss extends it
    hit <- hit + state[k] * q               # run reaches k
    state <- new
  }
  hit
}
