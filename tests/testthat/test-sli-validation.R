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
