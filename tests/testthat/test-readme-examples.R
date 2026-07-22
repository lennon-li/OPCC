testthat::test_that("README DA example uses a postal code with M2 coverage", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  result <- pc_to_geo("M5V 3A8", level = "DA")
  testthat::expect_gt(nrow(result), 0)
  testthat::expect_true("M5V 3A8" %in% result$postal_code)
})

testthat::test_that("README point example returns GeoNames point evidence", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  result <- pc_to_point("K1A 0A6")
  testthat::expect_gt(nrow(result), 0)
  testthat::expect_equal(result$point_source[1], "geonames")
})
