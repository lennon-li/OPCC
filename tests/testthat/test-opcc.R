testthat::test_that("normalization is strict and vectorized", {
  testthat::expect_equal(
    normalize_postal_code(c("k1a0a6", "K1A 0A6")),
    c("K1A 0A6", "K1A 0A6")
  )
  testthat::expect_true(is.na(normalize_postal_code("bad")))
  testthat::expect_error(normalize_postal_code("bad", strict = TRUE), "Invalid")
})

testthat::test_that("lookup retains all links unless explicit", {
  x <- data.frame(
    postal_code = c("K1A 0A6", "K1A 0A6"), DBUID = c("1", "2"),
    DAUID = c("a", "b"), allocation_weight = c(.6, .4),
    best_link = c(TRUE, FALSE), confidence = c(.6, .4),
    evidence_class = c("nar_address", "nar_address"), stringsAsFactors = FALSE
  )
  testthat::expect_equal(nrow(pc_to_geo("k1a0a6", correspondence = x)), 2)
  testthat::expect_equal(nrow(pc_to_geo("k1a0a6", correspondence = x, all_links = FALSE)), 1)
  testthat::expect_false("DBUID" %in% names(pc_to_geo("k1a0a6", "DA", correspondence = x)))
})

testthat::test_that("GeoNames points retain source and geography", {
  point_file <- testthat::test_path("fixtures", "geonames-points.csv.gz")
  out <- pc_to_point(c("K0A0A1", "K0A0A9"), point_file = point_file)
  testthat::expect_equal(nrow(out), 1)
  testthat::expect_equal(out$point_source, "geonames")
  testthat::expect_equal(out$DAUID, "35020133")
  testthat::expect_equal(attr(out, "unmatched"), "K0A 0A9")
})

testthat::test_that("candidate-style allocation validation accepts source-qualified rows", {
  x <- data.frame(
    postal_code = c("K0A 0A1", "K0A 0A2"), DBUID = c("1", "2"),
    DAUID = c("a", "b"), allocation_weight = c(1, 1), best_link = c(TRUE, TRUE),
    confidence = c(NA_real_, NA_real_), evidence_class = c("geonames_supplementary", "geonames_supplementary")
  )
  testthat::expect_true(all(tapply(x$allocation_weight, x$postal_code, sum) == 1))
})
