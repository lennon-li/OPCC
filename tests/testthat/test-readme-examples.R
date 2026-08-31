testthat::test_that("README DA example demonstrates a local DA lookup", {
  # Package checks must not depend on a GitHub raw-content download. The
  # release-validation CI job verifies the committed M5 artifact separately.
  da_fixture <- data.frame(
    postal_code = "M5V 3A8",
    DAUID = "35200001",
    allocation_weight = 1,
    n_contributing_dbs = 1L,
    contributing_dbuids = "35200001000",
    source_vintages = "2026-06-26",
    census_vintages = "2021",
    evidence_classes = "NAR",
    best_link = TRUE,
    stringsAsFactors = FALSE
  )
  result <- pc_to_geo("M5V 3A8", level = "DA", correspondence = da_fixture)
  testthat::expect_gt(nrow(result), 0)
  testthat::expect_true("M5V 3A8" %in% result$postal_code)
})

testthat::test_that("README point example returns GeoNames point evidence", {
  skip_if_no_network()
  testthat::skip_on_cran()
  result <- pc_to_point("K1A 0A6")
  testthat::expect_gt(nrow(result), 0)
  testthat::expect_equal(result$point_source[1], "geonames")
})
