# Write exact results from the R engine for the JavaScript tests to compare
# against. Run from the repository root; build_site.R does this on every build.

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

# Settings chosen to cover both wheels, table limits, overshooting strategies
# and targets that are not a multiple of the bankroll
scenarios <- list(
  list(bankroll = 400, goal = 800, unit = 5, table_max = Inf, wheel = "american"),
  list(bankroll = 400, goal = 425, unit = 5, table_max = Inf, wheel = "american"),
  list(bankroll = 400, goal = 800, unit = 5, table_max = 100, wheel = "american"),
  list(bankroll = 300, goal = 700, unit = 10, table_max = 500, wheel = "european"),
  list(bankroll = 100, goal = 1000, unit = 5, table_max = Inf, wheel = "european"),
  list(bankroll = 1000, goal = 2000, unit = 5, table_max = Inf, wheel = "american")
)

rows <- list()
for (scenario in scenarios) {
  p <- if (scenario$wheel == "american") P_AMERICAN else P_EUROPEAN
  for (id in names(all_strategies())) {
    r <- solve_exact(all_strategies()[[id]], scenario$bankroll, p, scenario$unit,
                     scenario$goal, scenario$table_max)
    rows[[length(rows) + 1]] <- sprintf(
      '{"strategy":"%s","bankroll":%s,"goal":%s,"unit":%s,"tableMax":%s,"wheel":"%s","pGoal":%.15g,"expWagered":%.15g,"expSpins":%.15g,"expResult":%.15g}',
      id, scenario$bankroll, scenario$goal, scenario$unit,
      if (is.finite(scenario$table_max)) scenario$table_max else "null",
      scenario$wheel, r$p_goal, r$exp_wagered, r$exp_spins, r$exp_result
    )
  }
}

writeLines(c("[", paste(rows, collapse = ",\n"), "]"), "explorer/tests/reference.json")
