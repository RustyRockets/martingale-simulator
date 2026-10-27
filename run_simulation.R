# Reproduces the charts and numbers in the README.
#
# Setup: American roulette, always betting red (18 winning pockets out of 38),
# $5 base bet, $400 bankroll. Each simulated player plays until the bankroll
# is gone, so "everyone goes broke" is true by construction and is NOT the
# finding. The interesting questions are how long it takes, how high players
# get before the end, and how many would have succeeded had they walked away.
source("martingale.R")
set.seed(2024)  # fixed seed so the README numbers are reproducible

p_red <- 18/38
base_bet <- 5
bankroll <- 400
n_players <- 10000

# one example run, saved as the README's first chart
example <- martingale(base_bet, bankroll, p_red, reverse = FALSE, plot = TRUE)
ggsave("images/single_run.png", example$plot, width = 8, height = 4.5, dpi = 150, bg = "white")

# simulate many players, recording how long each lasts and their peak bankroll
spins_to_bust <- c()
max_cash <- c()
for(i in 1:n_players){
  results <- martingale(base_bet, bankroll, p_red, reverse = FALSE, plot = FALSE)
  spins_to_bust[i] <- results$trials
  max_cash[i] <- max(results$total_cash)
}

summary(spins_to_bust)
summary(max_cash)

# What if every player had walked away as soon as they doubled their money?
# A player "makes it" if their peak bankroll ever reached 2x the start;
# everyone else loses the full bankroll. Because each run is a single path,
# the peak tells us exactly whether the walk-away target was hit first.
p_double <- mean(max_cash >= 2*bankroll)
expected_result <- p_double*bankroll - (1 - p_double)*bankroll
cat(sprintf("Share of players who doubled before going broke: %.1f%%\n", 100*p_double))
cat(sprintf("Average result per player with a walk-away-at-2x rule: $%.0f\n", expected_result))

gg_bust <- ggplot(data.frame(spins = spins_to_bust), aes(x = spins)) +
  geom_histogram(bins = 60, fill = "darkmagenta", alpha = 0.8) +
  scale_x_log10() +
  theme_minimal() +
  labs(
    x = "Spins until the $400 bankroll is gone (log scale)",
    y = "Number of simulated gamblers",
    title = "10,000 Martingale players at the roulette table",
    subtitle = "$5 starting bet, doubling after every loss, playing until broke"
  )
ggsave("images/spins_to_bust.png", gg_bust, width = 8, height = 4.5, dpi = 150, bg = "white")
