# Simulation charts for the report. These functions need ggplot2 attached by the
# caller; nothing else in R/ depends on it.

CHART_INK <- "#1c1d1f"
CHART_MUTED <- "#5d6066"
CHART_GRID <- "#e3e5e8"

# Fill colors for the three states a player can be in
STATUS_COLORS <- c("Reached target" = "#1baf7a", "Still playing" = "#d9dde2",
                   "Went broke" = "#5d6066")

# Shared look: recessive grid, left-aligned titles, no legend unless asked for
theme_report <- function(base_size = 14) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(color = CHART_GRID),
      plot.title = ggplot2::element_text(face = "bold", size = ggplot2::rel(1.1)),
      plot.subtitle = ggplot2::element_text(color = CHART_MUTED, size = ggplot2::rel(0.85)),
      axis.text = ggplot2::element_text(size = ggplot2::rel(0.9)),
      plot.title.position = "plot",
      plot.margin = ggplot2::margin(6, 16, 6, 6),  # room for the last axis label
      legend.position = "none"
    )
}

# The share of players in each state after every spin, from 0 to max_spin.
# Only needs each session's length and outcome, so it can use every player.
status_over_time <- function(spins, reached_goal, max_spin) {
  t <- 0:max_spin
  won <- sapply(t, function(x) mean(spins <= x & reached_goal))
  broke <- sapply(t, function(x) mean(spins <= x & !reached_goal))
  data.frame(
    spin = rep(t, 3),
    status = factor(rep(names(STATUS_COLORS), each = length(t)), levels = names(STATUS_COLORS)),
    share = c(won, 1 - won - broke, broke)
  )
}

# Count how many sessions were at each (spin, cash) cell of a regular grid.
# Finished sessions drop out, so the counts cover players still at the table.
session_density <- function(runs, max_spin, max_cash, nx = 90, ny = 60) {
  nx <- min(nx, max_spin)
  x_step <- max_spin / nx
  y_step <- max_cash / ny
  counts <- matrix(0, nx, ny)

  for (run in runs) {
    keep <- seq_along(run$cash) <= max_spin & run$cash > 0 & run$cash < max_cash
    if (isTRUE(run$reached_goal)) keep[length(keep)] <- FALSE  # already left the table
    if (!any(keep)) next
    i <- pmin(ceiling(which(keep) / x_step), nx)
    j <- pmin(floor(run$cash[keep] / y_step) + 1, ny)
    cell <- table(i + (j - 1) * nx)
    index <- as.integer(names(cell))
    counts[index] <- counts[index] + as.numeric(cell)
  }

  data.frame(
    spin = rep((seq_len(nx) - 0.5) * x_step, times = ny),
    cash = rep((seq_len(ny) - 0.5) * y_step, each = nx),
    n = as.vector(counts)
  )
}

# The run closest to the median player on both peak cash and session length,
# so the highlighted line is a typical session rather than a dramatic one.
typical_run <- function(runs) {
  peaks <- sapply(runs, `[[`, "peak")
  spins <- sapply(runs, `[[`, "spins")
  runs[[which.min(abs(log(peaks / median(peaks))) + abs(log(spins / median(spins))))]]
}

# Heat map of where the money is, spin by spin. Counts are shaded on a cube-root
# scale: enough to keep the fainter bands of players recovering from big losses
# visible, while the ridge still fades as players go broke, which a log scale hid.
plot_session_density <- function(density, bankroll, goal = NULL, typical = NULL,
                                 base_size = 14, text_size = 4) {
  max_spin <- max(density$spin) + (density$spin[2] - density$spin[1]) / 2
  max_cash <- max(density$cash) + (density$cash[density$cash > min(density$cash)][1] - min(density$cash)) / 2

  # Bold play can finish before there is anything to draw
  if (sum(density$n) == 0) {
    return(
      ggplot2::ggplot() +
        ggplot2::annotate("text", x = 0, y = 0, size = text_size, color = CHART_MUTED,
                          label = "Every session ended too quickly to chart.\nSee how they ended alongside.") +
        ggplot2::theme_void()
    )
  }

  g <- ggplot2::ggplot(density, ggplot2::aes(spin, cash)) +
    ggplot2::geom_raster(ggplot2::aes(fill = n^(1 / 3)), interpolate = TRUE) +
    ggplot2::scale_fill_gradientn(colors = c("#ffffff", "#d6e6f8", "#7fb0e6", "#2a78d6", "#0d3b7a")) +
    ggplot2::geom_hline(yintercept = bankroll, color = CHART_MUTED, linetype = "dashed", linewidth = 0.4) +
    ggplot2::annotate("text", x = max_spin, y = bankroll, label = "Start", hjust = 1.1, vjust = 1.5,
                      size = text_size - 0.4, color = CHART_INK)

  if (!is.null(goal)) {
    g <- g +
      ggplot2::geom_hline(yintercept = goal, color = CHART_MUTED, linetype = "dashed", linewidth = 0.4) +
      ggplot2::annotate("text", x = max_spin, y = goal, label = "Target", hjust = 1.1, vjust = 1.5,
                        size = text_size - 0.4, color = CHART_INK)
  }

  if (!is.null(typical)) {
    line <- data.frame(spin = c(0, seq_along(typical$cash)), cash = c(bankroll, typical$cash))
    g <- g + ggplot2::geom_line(data = line, color = CHART_INK, linewidth = 0.55)
  }

  g +
    ggplot2::scale_y_continuous(labels = scales::dollar) +
    ggplot2::coord_cartesian(xlim = c(0, max_spin), ylim = c(0, max_cash), expand = FALSE) +
    ggplot2::labs(x = "Spin", y = NULL) +
    theme_report(base_size) +
    ggplot2::theme(panel.grid = ggplot2::element_blank())
}

# Stacked area of every player's state over time
plot_status <- function(status, base_size = 14) {
  ggplot2::ggplot(status, ggplot2::aes(spin, share, fill = status)) +
    ggplot2::geom_area(color = "white", linewidth = 0.4) +
    ggplot2::scale_fill_manual(values = STATUS_COLORS, name = NULL) +
    ggplot2::scale_y_continuous(labels = scales::percent) +
    ggplot2::coord_cartesian(expand = FALSE) +
    ggplot2::labs(x = "Spin", y = NULL) +
    theme_report(base_size) +
    ggplot2::theme(legend.position = "top", legend.justification = "left",
                   legend.margin = ggplot2::margin(0, 0, 0, 0),
                   legend.box.spacing = ggplot2::unit(2, "pt"),
                   legend.key.size = ggplot2::unit(0.8, "lines"),
                   legend.text = ggplot2::element_text(size = ggplot2::rel(0.8)),
                   panel.grid = ggplot2::element_blank())
}
