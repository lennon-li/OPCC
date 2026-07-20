test_that("SLI validation helper file is available", {
  helper <- testthat::test_path("helper-sli-validation.R")
  testthat::expect_true(file.exists(helper))
})

test_that("postal code normalisation works", {
  expect_equal(sli_normalize_postal_code("k1a0b1"), "K1A 0B1")
  expect_equal(sli_normalize_postal_code("  k1a 0b1 "), "K1A 0B1")
  expect_equal(sli_normalize_postal_code("K1A0B1"), "K1A 0B1")
  expect_equal(sli_normalize_postal_code("K1A 0B1"), "K1A 0B1")
})

test_that("haversine distance is correct", {
  # One degree of latitude is approximately 111.19 km.
  d <- sli_haversine_km(0, 0, 1, 0)
  expect_true(d > 110 && d < 112)
  expect_equal(sli_haversine_km(45, -75, 45, -75), 0, tolerance = 1e-9)
})

test_that("centroid reader validates required columns", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8"),
    latitude = c(45.42, 43.64),
    longitude = c(-75.70, -79.39),
    point_source = c("nar_centroid", "geonames")
  ), tmp, row.names = FALSE)
  df <- sli_read_centroids(tmp)
  expect_equal(nrow(df), 2)
  expect_equal(df$postal_code, c("K1A 0B1", "M5V 3A8"))

  bad <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1), bad, row.names = FALSE)
  expect_error(sli_read_centroids(bad), "Missing required centroid columns")
})

test_that("SLI reader accepts flexible column names", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(
    pc = c("K1A 0B1", "M5V 3A8"),
    lat = c(45.42, 43.64),
    long = c(-75.70, -79.39)
  ), tmp, row.names = FALSE)
  df <- sli_read_sli(tmp)
  expect_equal(nrow(df), 2)
  expect_equal(df$postal_code, c("K1A 0B1", "M5V 3A8"))
})

test_that("metrics computation stratifies by source", {
  centroids <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8", "H3A 0G4"),
    latitude = c(45.42, 43.64, 45.50),
    longitude = c(-75.70, -79.39, -73.57),
    point_source = c("nar_centroid", "geonames", "nar_centroid")
  )
  sli <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8", "H3A 0G4"),
    latitude = c(45.42, 43.65, 45.51),
    longitude = c(-75.70, -79.40, -73.58)
  )
  m <- sli_compute_metrics(centroids, sli)
  expect_equal(m$coverage$matched_postal_codes, 3)
  expect_equal(nrow(m$by_source), 2)
  expect_true(all(m$by_source$point_source %in% c("nar_centroid", "geonames")))
})

test_that("synthetic QA is deterministic", {
  centroids <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8", "H3A 0G4", "V6B 1A1"),
    latitude = c(45.42, 43.64, 45.50, 49.28),
    longitude = c(-75.70, -79.39, -73.57, -123.12),
    point_source = c("nar_centroid", "geonames", "nar_centroid", "geonames")
  )
  q1 <- sli_make_synthetic_qa(centroids, seed = 123L, n_per_source = 2L)
  q2 <- sli_make_synthetic_qa(centroids, seed = 123L, n_per_source = 2L)
  expect_equal(q1, q2)
  expect_equal(nrow(q1), 4)
})

test_that("M1 release artifact verifies against its manifest", {
  manifest_path <- testthat::test_path("../../releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json")
  gz_path <- testthat::test_path("../../releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz")
  testthat::skip_if_not(file.exists(manifest_path))
  testthat::skip_if_not(file.exists(gz_path))

  manifest <- jsonlite::read_json(manifest_path)
  df <- sli_verify_m1_artifact(gz_path, manifest)

  expect_equal(nrow(df), manifest$artifact$total_rows)
  expect_true(all(c("postal_code", "latitude", "longitude", "point_source") %in% names(df)))
})

test_that("tampered M1 manifest fails verification", {
  manifest_path <- testthat::test_path("../../releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json")
  gz_path <- testthat::test_path("../../releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz")
  testthat::skip_if_not(file.exists(manifest_path))
  testthat::skip_if_not(file.exists(gz_path))

  manifest <- jsonlite::read_json(manifest_path)
  manifest$artifact$csv_sha256 <- paste(rep("0", 64), collapse = "")
  tmp_manifest <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(manifest, tmp_manifest, auto_unbox = TRUE, pretty = TRUE)

  expect_error(
    sli_verify_m1_artifact(gz_path, jsonlite::read_json(tmp_manifest)),
    "hash mismatch"
  )
})

test_that("producer revision validation works", {
  # Skip if helper function not available (e.g., on CI without git)
  testthat::skip_if_not(exists("sli_validate_producer_ref"))
  testthat::skip_on_cran()

  # Get current HEAD as a valid producer ref
  head_sha <- tryCatch({
    res <- system("git rev-parse HEAD", intern = TRUE)
    # Check if result looks like a SHA (40 hex chars)
    if (length(res) > 0 && grepl("^[0-9a-f]{40}$", res[1])) res[1] else NULL
  }, error = function(e) NULL, warning = function(w) NULL)
  testthat::skip_if(is.null(head_sha))

  # Valid ref with existing scripts should succeed
  result <- sli_validate_producer_ref(head_sha, c("scripts/sli_validate.R"))
  expect_equal(result, head_sha)

  # Non-existent ref should fail
  expect_error(
    sli_validate_producer_ref("0000000000000000000000000000000000000000",
                              c("scripts/sli_validate.R")),
    "does not contain script"
  )

  # Valid ref but missing script should fail
  expect_error(
    sli_validate_producer_ref(head_sha, c("scripts/nonexistent.R")),
    "does not contain script"
  )
})

test_that("malformed producer refs are rejected", {
  testthat::skip_if_not(exists("sli_validate_producer_ref"))
  testthat::skip_on_cran()

  # Empty string
  expect_error(
    sli_validate_producer_ref("", c("scripts/sli_validate.R")),
    "required"
  )

  # NULL
  expect_error(
    sli_validate_producer_ref(NULL, c("scripts/sli_validate.R")),
    "required"
  )

  # Invalid git ref (not a commit)
  expect_error(
    sli_validate_producer_ref("not-a-valid-ref", c("scripts/sli_validate.R")),
    "not found|invalid"
  )
})

test_that("manifest stores full 40-character SHA", {
  testthat::skip_if_not(exists("sli_validate_producer_ref"))
  testthat::skip_on_cran()

  # Get current HEAD
  head_sha <- tryCatch({
    res <- system("git rev-parse HEAD", intern = TRUE)
    if (length(res) > 0 && grepl("^[0-9a-f]{40}$", res[1])) res[1] else NULL
  }, error = function(e) NULL, warning = function(w) NULL)
  testthat::skip_if(is.null(head_sha))

  # Test with abbreviated SHA
  abbrev_sha <- substr(head_sha, 1, 7)
  result <- sli_validate_producer_ref(abbrev_sha, c("scripts/sli_validate.R"))

  # Should return full 40-character SHA, not the abbreviation
  expect_equal(nchar(result), 40)
  expect_equal(result, head_sha)
  expect_true(grepl("^[0-9a-f]{40}$", result))
})
