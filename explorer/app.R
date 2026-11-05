# Betting strategy explorer: a Shiny app that runs in the browser via
# Shinylive (webR). build_site.R copies the project's R/ folder next to this
# file before exporting, so the app uses exactly the same strategy, simulation
# and exact-solver code as the report.
#
# Charts come from R/plots.R, the same code the report uses.

library(shiny)
library(bslib)
library(ggplot2)

# The browser's R runs ggplot2 3.5, but Shinylive works out what to bundle from the
# newer ggplot2 installed locally, which dropped these dependencies. Missing any of
# them leaves a blank page. This block is never run; naming them gets them bundled.
if (FALSE) {
  library(MASS); library(mgcv); library(munsell); library(tibble); library(withr)
}

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

strategies <- all_strategies()
strategy_choices <- setNames(names(strategies), sapply(strategies, `[[`, "name"))

# Size limits keep the exact solver fast in the browser: its state space grows
# with (goal / base bet)^2 for the progressive strategies.
MAX_BANKROLL_UNITS <- 200
MAX_GOAL_UNITS <- 400

ui <- page_sidebar(
  title = "Betting strategy explorer",
  theme = bs_theme(version = 5, primary = "#1f6f66", base_font = "Inter, system-ui, sans-serif"),
  sidebar = sidebar(
    width = 290,
    selectInput("strategy", "Strategy", strategy_choices, selected = "martingale"),
    radioButtons("wheel", "Wheel", inline = TRUE,
                 c("American (0, 00)" = "american", "European (0)" = "european")),
    numericInput("bankroll", "Starting bankroll ($)", 400, min = 10, step = 50),
    selectInput("unit", "Base bet ($)", c(1, 5, 10, 25), selected = 5),
    numericInput("target", "Walk away after winning ($)", 400, min = 5, step = 25),
    selectInput("table_max", "Table maximum",
                c("No limit" = "Inf", "$100" = "100", "$500" = "500",
                  "$1,000" = "1000", "$5,000" = "5000"), selected = "Inf"),
    helpText("A limit only changes the result if the strategy would bet more than it."),
    sliderInput("n_players", "Simulated players", min = 100, max = 2000, value = 500, step = 100,
                ticks = FALSE),
    actionButton("run", "Run", class = "btn-primary"),
    helpText("Exact numbers come from solving the game as a Markov chain. ",
             "The charts come from simulated players.")
  ),
  # Keep value-box numbers on one line in narrow windows
  tags$style(".bslib-value-box .value-box-value { font-size: 1.6rem; white-space: nowrap; }"),
  uiOutput("validation"),
  layout_columns(
    fill = FALSE,
    value_box("Chance of reaching target", textOutput("p_goal"), theme = "primary"),
    value_box("Average result", textOutput("exp_result")),
    value_box("Average total bet", textOutput("exp_wagered")),
    value_box("Average spins", textOutput("exp_spins"))
  ),
  layout_columns(
    card(card_header("Where the money is"), plotOutput("paths", height = 320),
         card_footer(textOutput("density_note"))),
    card(card_header("Where every player stands"), plotOutput("outcomes", height = 320),
         card_footer(textOutput("sim_note")))
  )
)

server <- function(input, output, session) {

  # Collect and check the settings when "Run" is pressed (and once at start).
  settings <- eventReactive(input$run, {
    unit <- as.numeric(input$unit)
    bankroll <- input$bankroll
    target <- input$target
    list(
      strategy = strategies[[input$strategy]],
      p = if (input$wheel == "american") P_AMERICAN else P_EUROPEAN,
      unit = unit,
      bankroll = bankroll,
      goal = bankroll + target,
      table_max = as.numeric(input$table_max),
      n = input$n_players,
      problem = if (!isTruthy(bankroll) || !isTruthy(target) || bankroll < unit || target <= 0) {
        "The bankroll must be at least one base bet and the target must be positive."
      } else if (bankroll / unit > MAX_BANKROLL_UNITS || (bankroll + target) / unit > MAX_GOAL_UNITS) {
        sprintf("To keep the browser responsive, keep the bankroll within %d base bets and bankroll + target within %d base bets.",
                MAX_BANKROLL_UNITS, MAX_GOAL_UNITS)
      } else NULL
    )
  }, ignoreNULL = FALSE)

  output$validation <- renderUI({
    s <- settings()
    if (!is.null(s$problem)) div(class = "alert alert-warning", s$problem)
  })

  exact <- reactive({
    s <- settings()
    req(is.null(s$problem))
    solve_exact(s$strategy, s$bankroll, s$p, s$unit, s$goal, s$table_max)
  })

  # Cap the total number of simulated spins so long sessions (e.g. flat bets
  # toward a distant target) stay quick in the browser. The exact solver
  # gives the expected session length up front, so the cap is applied before
  # simulating.
  MAX_SIM_SPINS <- 5e5

  sims <- reactive({
    s <- settings()
    req(is.null(s$problem))
    n <- min(s$n, max(100, floor(MAX_SIM_SPINS / exact()$exp_spins)))
    set.seed(1)
    runs <- lapply(seq_len(n), function(i) {
      simulate_player(s$strategy, s$bankroll, s$p, s$unit, s$goal, s$table_max, path = TRUE)
    })
    many <- data.frame(
      spins = sapply(runs, `[[`, "spins"),
      reached_goal = sapply(runs, `[[`, "reached_goal"),
      result = sapply(runs, `[[`, "final") - s$bankroll
    )
    # Chart up to the point where nearly every session has ended
    max_spin <- max(5, ceiling(quantile(many$spins, 0.95)))
    list(runs = runs, many = many, max_spin = max_spin, capped = n < s$n)
  })

  dollars <- function(x) {
    paste0(ifelse(x < 0, "−$", "$"), formatC(abs(round(x)), format = "d", big.mark = ","))
  }

  output$p_goal <- renderText(sprintf("%.1f%%", 100 * exact()$p_goal))
  output$exp_result <- renderText(dollars(exact()$exp_result))
  output$exp_wagered <- renderText(dollars(exact()$exp_wagered))
  output$exp_spins <- renderText(formatC(round(exact()$exp_spins), format = "d", big.mark = ","))

  output$paths <- renderPlot({
    s <- settings(); req(is.null(s$problem))
    sim <- sims()
    density <- session_density(sim$runs, sim$max_spin, s$goal * 1.05, nx = 60, ny = 40)
    plot_session_density(density, s$bankroll, s$goal, typical_run(sim$runs),
                         base_size = 13, text_size = 3.6)
  })

  output$density_note <- renderText({
    sprintf("Darker means more players held that amount. The black line is a typical session. Showing the first %s spins.",
            format(sims()$max_spin, big.mark = ","))
  })

  # Sessions end in one of two ways, and this shows when, not just how many
  output$outcomes <- renderPlot({
    s <- settings(); req(is.null(s$problem))
    sim <- sims()
    plot_status(status_over_time(sim$many$spins, sim$many$reached_goal, sim$max_spin),
                base_size = 13, short_labels = TRUE)
  })

  output$sim_note <- renderText({
    m <- sims()$many
    # 95% margins of error, so sampling noise isn't mistaken for a disagreement
    moe_p <- 1.96 * sqrt(mean(m$reached_goal) * (1 - mean(m$reached_goal)) / nrow(m))
    moe_r <- 1.96 * sd(m$result) / sqrt(nrow(m))
    note <- sprintf("%s simulated players: %.1f%% (\u00b1%.1f) reached the target, average result %s (\u00b1%s). Exact: %.1f%%, %s.",
                    format(nrow(m), big.mark = ","), 100 * mean(m$reached_goal), 100 * moe_p,
                    dollars(mean(m$result)), dollars(moe_r), 100 * exact()$p_goal, dollars(exact()$exp_result))
    if (sims()$capped) note <- paste(note, "Sessions this long are capped to keep the page responsive.")
    note
  })
}

shinyApp(ui, server)
