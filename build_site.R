# Build the published site into docs/ (served by GitHub Pages).
#
#   1. Run the test suite; stop if anything fails.
#   2. Render the Quarto report to docs/index.html.
#   3. Export the Shiny explorer with Shinylive to docs/explorer/, bundling
#      a copy of R/ so the browser runs the same code as the report.
#   4. Refresh the README charts in images/.
#
# Run from the repository root:  Rscript build_site.R
# Requires: Quarto, and the R packages listed in the README.

testthat::test_dir("tests/testthat", stop_on_failure = TRUE)

status <- system2("quarto", c("render", "report/index.qmd"))
if (status != 0) stop("Quarto render failed")

app_dir <- file.path(tempdir(), "explorer-build")
unlink(app_dir, recursive = TRUE)
dir.create(file.path(app_dir, "R"), recursive = TRUE)
file.copy("explorer/app.R", app_dir)
file.copy(list.files("R", full.names = TRUE), file.path(app_dir, "R"))
unlink("docs/explorer", recursive = TRUE)
shinylive::export(app_dir, "docs/explorer")

# GitHub Pages: serve files as-is (no Jekyll processing)
file.create("docs/.nojekyll")

# README images are copies of the report's charts
figs <- "docs/index_files/figure-html"
file.copy(file.path(figs, "compare-1.png"), "images/strategy_comparison.png", overwrite = TRUE)
file.copy(file.path(figs, "identity-1.png"), "images/edge_identity.png", overwrite = TRUE)
file.copy(file.path(figs, "win-rate-1.png"), "images/win_rate.png", overwrite = TRUE)
file.copy(file.path(figs, "single-run-1.png"), "images/single_run.png", overwrite = TRUE)
