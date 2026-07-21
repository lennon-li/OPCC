test_that("pc_to_geo with DA level and correspondence works correctly", {
  da_mock <- data.frame(
    postal_code = "K1A 0A6",
    DAUID = "35061614",
    allocation_weight = 1.0,
    n_contributing_dbs = 1,
    contributing_dbuids = "35061614000",
    source_vintages = "2026-06-26",
    census_vintages = "2021",
    evidence_classes = "NAR",
    best_link = TRUE,
    stringsAsFactors = FALSE
  )

  # Ensure best_link is logical and others are character/numeric appropriately
  da_mock$best_link <- as.logical(da_mock$best_link)
  da_mock$allocation_weight <- as.numeric(da_mock$allocation_weight)
  da_mock$n_contributing_dbs <- as.numeric(da_mock$n_contributing_dbs)

  result <- pc_to_geo(c("K1A0A6", "H0H0H0"), level = "DA", correspondence = da_mock)

  # Check that the matched row is returned
  expect_equal(nrow(result), 1)
  expect_equal(result$postal_code, "K1A 0A6")
  expect_equal(result$DAUID, "35061614")

  # Check that unmatched postal code is stored in unmatched attribute
  expect_true("unmatched" %in% names(attributes(result)))
  expect_equal(attributes(result)$unmatched, "H0H 0H0")
})
