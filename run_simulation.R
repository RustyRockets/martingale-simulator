# run the simulation and plot the output
# try different parameters to see the effect
source("martingale.R")
set.seed(2024)

# American roulette, betting red: 18 winning pockets out of 38
p_red <- 18/38

# one example run
example <- martingale(5, 400, p_red, reverse = FALSE, plot = TRUE)
ggsave("images/single_run.png", example$plot, width = 8, height = 4.5, dpi = 150, bg = "white")

# 10,000 runs, each played until the bankroll is gone
spins_to_bust <- c()
max_cash <- c()
for(i in 1:10000){
  results <- martingale(5, 400, p_red, reverse = FALSE, plot = FALSE)
  spins_to_bust[i] <- results$trials
  max_cash[i] <- max(results$total_cash)
}

summary(spins_to_bust)
summary(max_cash)

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
