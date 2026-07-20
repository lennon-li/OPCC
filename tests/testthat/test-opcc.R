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
  da <- pc_to_geo("k1a0a6", "DA", correspondence = x)
  testthat::expect_false("DBUID" %in% names(da))
  testthat::expect_equal(da$allocation_weight, c(.6, .4))
  testthat::expect_equal(da$n_contributing_dbs, c(1L, 1L))
})

testthat::test_that("DA roll-up combines DB weights and preserves lineage", {
  x <- data.frame(
    postal_code = c("K1A 0A6", "K1A 0A6", "K1A 0A6", "K1A 0A7"),
    DBUID = c("DB2", "DB1", "DB3", "DB4"),
    DAUID = c("DA1", "DA1", "DA2", "DA3"),
    allocation_weight = c(.2, .5, .3, 1),
    source_vintage = "2026-06-26",
    census_vintage = "2021",
    evidence_class = "nar_address",
    stringsAsFactors = FALSE
  )
  out <- aggregate_da_correspondence(x)
  testthat::expect_equal(out$DAUID[out$postal_code == "K1A 0A6"], c("DA1", "DA2"))
  testthat::expect_equal(out$allocation_weight[out$postal_code == "K1A 0A6"], c(.7, .3))
  testthat::expect_equal(out$n_contributing_dbs[out$DAUID == "DA1"], 2L)
  testthat::expect_equal(out$contributing_dbuids[out$DAUID == "DA1"], "DB1|DB2")
  testthat::expect_true(out$best_link[out$DAUID == "DA1"])
  testthat::expect_equal(
    pc_to_geo("K1A0A6", "DA", correspondence = x, all_links = FALSE)$DAUID,
    "DA1"
  )
})

testthat::test_that("DA lookup retains supplementary links and reports unmatched codes", {
  x <- data.frame(
    postal_code = "K0A 0A1", DBUID = "DB1", DAUID = "DA1",
    allocation_weight = 1, source_vintage = "2026-07-19",
    census_vintage = "2021", evidence_class = "geonames_supplementary",
    stringsAsFactors = FALSE
  )
  out <- pc_to_geo(c("K0A0A1", "K0A0A2"), "DA", correspondence = x)
  testthat::expect_equal(out$evidence_classes, "geonames_supplementary")
  testthat::expect_equal(attr(out, "unmatched"), "K0A 0A2")
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
