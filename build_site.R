# Build the published site into docs/ (served by GitHub Pages).
#
#   1. Run the R tests, then check the explorer's JavaScript engine against R.
#   2. Render the Quarto report to docs/index.html.
#   3. Copy the explorer to docs/explorer/.
#   4. Refresh the README charts in images/.
#
# Run from the repository root:  Rscript build_site.R
# Requires: Quarto, Node.js, and the R packages listed in the README.

testthat::test_dir("tests/testthat", stop_on_failure = TRUE)

source("explorer/tests/make_reference.R")
if (system2("node", c("--test", "explorer/tests/engine.test.js")) != 0) {
  stop("The explorer's JavaScript engine disagrees with R")
}

status <- system2("quarto", c("render", "report/index.qmd"))
if (status != 0) stop("Quarto render failed")

unlink("docs/explorer", recursive = TRUE)
dir.create("docs/explorer")
file.copy(file.path("explorer", c("index.html", "explorer.css", "engine.js", "app.js")), "docs/explorer")

# GitHub Pages: serve files as-is (no Jekyll processing)
file.create("docs/.nojekyll")

# README images are copies of the report's charts
figs <- "docs/index_files/figure-html"
file.copy(file.path(figs, "compare-1.png"), "images/strategy_comparison.png", overwrite = TRUE)
file.copy(file.path(figs, "tail-1.png"), "images/win_rate.png", overwrite = TRUE)
