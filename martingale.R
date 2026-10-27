# Martingale betting simulator.
#
# Classic Martingale: bet a base amount; after every loss double the bet, after
# every win go back to the base bet. Reverse Martingale does the opposite
# (double after wins). Each call simulates one gambler from their starting
# bankroll until they go broke or hit one of the optional stop rules.

# libraries
library(tidyverse)

# martingale function
# bet: starting bet, cash: starting bankroll, p: probability of winning one bet
# stop_condn: stop once the bet would exceed this share of cash in hand
# stop_factor: stop once cash reaches this multiple of the starting bankroll
# reverse: double after wins instead of losses (reverse Martingale)
# stop_on_next_win: when stop_condn triggers, keep playing until the next win, then stop
# plot: build a ggplot of the bankroll over time
#
# Returns a list with one entry per spin: bet, cash before the spin, outcome
# (1 = win, 0 = loss), total_cash after the spin, plus trials (number of spins)
# and plot (NULL when plot = FALSE).
martingale <- function(bet, cash, p, stop_condn = Inf, stop_factor = Inf, reverse = FALSE,
                       plot = TRUE, stop_on_next_win = TRUE){

  bet_vec <- vector(mode = "numeric")
  cash_vec <- vector(mode = "numeric")
  outcome <- vector(mode = "numeric")
  winnings <- vector(mode = "numeric")
  total_cash <- vector(mode = "numeric")
  trial <- 0
  total_cash[1] <- cash
  stop_trigger <- FALSE

  while(total_cash[max(trial, 1)] > 0){

    # iterate through trials
    trial <- trial + 1

    # update cash pool
    if(trial == 1){
      cash_vec[trial] <- cash
    }else{
      cash_vec[trial] <- total_cash[trial-1]
    }

    # set bet
    if(!reverse){
      if(trial == 1 || outcome[trial - 1] == 1){
        bet_vec[trial] <- bet
      }else{
        bet_vec[trial] <- min(2*bet_vec[trial-1], cash_vec[trial]) # if there isn't enough to double the bet just bet what is left
      }
    }else{
      if(trial == 1 || outcome[trial - 1] == 0){
        bet_vec[trial] <- bet
      }else{
        bet_vec[trial] <- min(2*bet_vec[trial-1], cash_vec[trial]) # if there isn't enough to double the bet just bet what is left
      }
    }

    # stop condition
    if(bet_vec[trial]/cash_vec[trial] > stop_condn){
      if(stop_on_next_win & !reverse){
        stop_trigger <- TRUE
      }else{
        outcome[trial] <- NA
        winnings[trial] <- NA
        total_cash[trial] <- cash_vec[trial]
        break
      }
    }

    outcome[trial] <- sample(c(0,1), 1, prob = c(1-p, p))
    winnings[trial] <- bet_vec[trial]*outcome[trial] - bet_vec[trial]*(1-outcome[trial])
    total_cash[trial] <- cash_vec[trial] + winnings[trial]

    # stop conditions
    if(total_cash[trial] >= stop_factor*cash) break
    if(stop_trigger & outcome[trial] == 1) break
  }

  # make the plot
  gg <- NULL
  if(plot){
    df <- data.frame(trials = 1:trial, cash = total_cash)
    gg <- ggplot() +
      geom_line(data = df, mapping = aes(x = trials, y = cash), col = "darkmagenta", lty = 1, linewidth = 1) +
      geom_hline(yintercept = cash_vec[1], col = "grey", lty = 2) +
      theme_minimal() +
      labs(
        x = "Number of spins",
        y = "Total cash in hand",
        title = ifelse(reverse, "Reverse Martingale strategy", "Martingale strategy"),
        subtitle = "The growth and decline of the gambler's cash pool - it always ends the same way"
      ) +
      ylim(0, NA)
  }

  return(list(
    bet = bet_vec,
    cash = cash_vec,
    outcome = outcome,
    total_cash = total_cash,
    trials = trial,
    plot = gg
    ))
}
