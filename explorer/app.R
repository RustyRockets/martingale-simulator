# Betting strategy explorer: a Shiny app that runs in the browser via
# Shinylive (webR). build_site.R copies the project's R/ folder next to this
# file before exporting, so the app uses exactly the same strategy, simulation
# and exact-solver code as the report.
#
# Plots use base R graphics rather than ggplot2 to keep the in-browser
# download small and the first load fast.

library(shiny)
library(bslib)

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

strategies <- all_strategies()
strategy_choices <- setNames(names(strategies), sapply(strategies, `[[`, "name"))

# Size limits keep the exact solver fast in the browser: its state space grows
# with (goal / base bet)^2 for the progressive strategies.
MAX_BANKROLL_UNITS <- 200
MAX_GOAL_UNITS <- 400

ink <- "#1c1d1f"; muted <- "#5d6066"; accent <- "#2a78d6"; line_col <- "#e3e5e8"

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
    sliderInput("n_players", "Simulated players", min = 100, max = 2000, value = 500, step = 100),
    actionButton("run", "Run", class = "btn-primary"),
    helpText("Exact numbers come from solving the game as a Markov chain. ",
             "The charts come from simulated players.")
  ),
  # Keep value-box numbers on one line in narrow windows
  tags$style(".bslib-value-box .value-box-value { font-size: 1.6rem; white-space: nowrap; }"),
  uiOutput("validation"),
  layout_columns(
    fill = FALSE,
    value_box("Chance of target", textOutput("p_goal"), theme = "primary"),
    value_box("Average result", textOutput("exp_result")),
    value_box("Average total bet", textOutput("exp_wagered")),
    value_box("Average spins", textOutput("exp_spins"))
  ),
  layout_columns(
    card(card_header("Twenty sample sessions"), plotOutput("paths", height = 320)),
    card(card_header("Results across all simulated players"), plotOutput("hist", height = 320),
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
    paths <- lapply(1:20, function(i) {
      simulate_player(s$strategy, s$bankroll, s$p, s$unit, s$goal, s$table_max, path = TRUE)
    })
    many <- simulate_many(n, s$strategy, s$bankroll, s$p, s$unit, s$goal, s$table_max)
    list(paths = paths, many = many, capped = n < s$n)
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
    paths <- sims()$paths
    max_spin <- max(sapply(paths, function(r) length(r$cash)), 1)
    par(mar = c(4, 4.5, 1, 1), col.axis = muted, fg = muted, family = "sans")
    plot(NA, xlim = c(0, max_spin), ylim = c(0, max(s$goal, sapply(paths, `[[`, "peak"))),
         xlab = "Spin", ylab = "Cash in hand ($)", las = 1, bty = "n")
    abline(h = pretty(c(0, s$goal)), col = line_col, lwd = 0.8)
    abline(h = s$bankroll, col = muted, lty = 2)
    abline(h = s$goal, col = "#1f6f66", lty = 3)
    for (r in paths) lines(c(0, seq_along(r$cash)), c(s$bankroll, r$cash),
                           col = adjustcolor(accent, 0.55), lwd = 1.2)
    # Label the reference lines directly, at the right edge above each line
    text(max_spin, s$bankroll, "Start", adj = c(1, -0.4), col = muted, cex = 0.85)
    text(max_spin, s$goal, "Target", adj = c(1, -0.4), col = "#1f6f66", cex = 0.85)
  })

  output$hist <- renderPlot({
    s <- settings(); req(is.null(s$problem))
    res <- sims()$many$result
    par(mar = c(4, 4.5, 1, 1), col.axis = muted, fg = muted, family = "sans")
    breaks <- pretty(range(res), n = 30)
    hist(res, breaks = breaks, col = accent, border = "white", main = NULL,
         xlab = "Result of the session ($)", ylab = "Players", las = 1)
    abline(v = 0, col = muted, lty = 2)
  })

  output$sim_note <- renderText({
    m <- sims()$many
    note <- sprintf("%s simulated players: %.1f%% reached the target, average result %s (exact: %.1f%%, %s).",
                    format(nrow(m), big.mark = ","), 100 * mean(m$reached_goal), dollars(mean(m$result)),
                    100 * exact()$p_goal, dollars(exact()$exp_result))
    if (sims()$capped) note <- paste(note, "Sessions this long are capped to keep the page responsive.")
    note
  })
}

shinyApp(ui, server)
