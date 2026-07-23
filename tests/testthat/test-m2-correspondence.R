script_path <- if (file.exists("scripts/m2_build_correspondence.R")) {
  "scripts/m2_build_correspondence.R"
} else {
  file.path("..", "..", "scripts", "m2_build_correspondence.R")
}
if (!file.exists(script_path)) {
  testthat::test_that("M2 builder tests are source-checkout tests", {
    testthat::skip("M2 build script is not installed with the runtime package")
  })
} else {
  source(script_path)

testthat::test_that("normalize_pc returns ANA NAN", {
  testthat::expect_equal(normalize_pc(c("k1a 0a6", "K1A0A7")), c("K1A 0A6", "K1A 0A7"))
  testthat::expect_true(is.na(normalize_pc("not-a-postal-code")))
})

testthat::test_that("M2 evidence weights and winner are deterministic", {
  data <- data.frame(
    postal_code = c("K1A 0A6", "K1A 0A6", "K1A 0A6", "K1A 0A6"),
    LOC_GUID = c("A1", "A2", "B1", "B2"),
    DBUID = c("DB2", "DB2", "DB1", "DB1"),
    DAUID = c("DA2", "DA2", "DA1", "DA1"),
    stringsAsFactors = FALSE
  )
  result <- aggregate_m2_evidence(data, "DAUID")
  testthat::expect_equal(sum(result$address_weight), 1)
  testthat::expect_equal(sum(result$best_link), 1)
  testthat::expect_equal(result$DBUID[result$best_link], "DB1")
  testthat::expect_equal(result$confidence, result$address_weight)
  testthat::expect_identical(anyDuplicated(result[c("postal_code", "DBUID")]), 0L)
})

testthat::test_that("M2 rejects missing and invalid observations", {
  testthat::expect_error(
    aggregate_m2_evidence(data.frame(postal_code = "K1A 0A6")),
    "Missing required aggregation columns"
  )
  invalid <- data.frame(
    postal_code = NA_character_, LOC_GUID = "A1", DBUID = "DB1",
    stringsAsFactors = FALSE
  )
  testthat::expect_error(aggregate_m2_evidence(invalid), "No valid NAR observations")
})

testthat::test_that("M2 output keeps the required contract", {
  data <- data.frame(
    postal_code = c("K1A 0A6", "K1A 0A6"),
    LOC_GUID = c("A1", "A2"),
    DBUID = c("DB1", "DB2"),
    DAUID = c("DA1", "DA2"),
    stringsAsFactors = FALSE
  )
  result <- aggregate_m2_evidence(data, "DAUID")
  required <- c("postal_code", "DBUID", "DAUID", "n_observations",
                "n_unique_addresses", "n_sources", "address_weight",
                "best_link", "confidence")
  testthat::expect_true(all(required %in% names(result)))
})

testthat::test_that("GeoNames point evidence is appended only when it has DB and DA", {
  nar <- aggregate_m2_evidence(data.frame(
    postal_code = "K1A 0A6", LOC_GUID = "A1", DBUID = "DB1", DAUID = "DA1",
    stringsAsFactors = FALSE
  ), "DAUID")
  nar$source_vintage <- "2026-06-26"
  nar$census_vintage <- "2021"
  rollup <- data.frame(
    postal_code = c("K1A 0A6", "K1A 0A7", "K1A 0A8"),
    point_source = "geonames",
    DBUID = c("DB1", "DB2", NA),
    DAUID_ADIDU = c("DA1", "DA2", NA),
    db_match_status = c(
      "matched_2021_ontario_db",
      "matched_2021_ontario_db",
      "unmatched_no_2021_ontario_db"
    ),
    latitude = c("45", "45", "45"), longitude = c("-75", "-75", "-75"),
    gn_accuracy = c("6", "6", "6"), stringsAsFactors = FALSE
  )
  path <- tempfile(fileext = ".csv")
  readr::write_csv(rollup, path)
  result <- append_geonames_supplementary(nar, path, "DAUID")
  validate_m2_result(result)
  testthat::expect_equal(nrow(result), 2)
  testthat::expect_equal(result$postal_code, c("K1A 0A6", "K1A 0A7"))
  testthat::expect_equal(result$evidence_class, c("nar_address", "geonames_supplementary"))
  testthat::expect_equal(result$gn_accuracy[[2]], 6)
  report <- attr(result, "opcc_point_assignment_report")
  testthat::expect_equal(report$matched_points, 2L)
  testthat::expect_equal(report$unmatched_points, 1L)
})

testthat::test_that("GeoNames DB status and geography identifiers are consistent", {
  nar <- aggregate_m2_evidence(data.frame(
    postal_code = "K1A 0A6",
    LOC_GUID = "A1",
    DBUID = "DB1",
    DAUID = "DA1",
    stringsAsFactors = FALSE
  ), "DAUID")
  nar$source_vintage <- "2026-06-26"
  nar$census_vintage <- "2021"
  rollup <- data.frame(
    postal_code = "K1A 0A7",
    point_source = "geonames",
    DBUID = NA_character_,
    DAUID_ADIDU = NA_character_,
    db_match_status = "matched_2021_ontario_db",
    latitude = "45",
    longitude = "-75",
    gn_accuracy = "6",
    stringsAsFactors = FALSE
  )
  path <- tempfile(fileext = ".csv")
  readr::write_csv(rollup, path)

  testthat::expect_error(
    append_geonames_supplementary(nar, path, "DAUID"),
    "inconsistent"
  )
})
}
