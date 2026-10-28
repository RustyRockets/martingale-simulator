# Load the project code once for all test files.
root <- normalizePath(file.path("..", ".."))
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}
