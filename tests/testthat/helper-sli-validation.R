# Load the source-checkout validation engine for package and script tests.
validation_helper <- testthat::test_path(
  "..",
  "..",
  "R",
  "validation-metrics.R"
)

if (file.exists(validation_helper)) {
  source(validation_helper)
}
