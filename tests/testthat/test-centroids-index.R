testthat::test_that("M1 centroid artifact is discoverable and pinned in the release index", {
  index_path <- testthat::test_path("..", "..", "inst", "extdata",
                                    "release-index.json")
  testthat::skip_if_not(file.exists(index_path))
  index <- jsonlite::read_json(index_path, simplifyVector = FALSE)
  spec <- index$m1_centroids[["2026-06-26"]]
  testthat::expect_false(is.null(spec))
  testthat::expect_true(grepl(
    "^https://raw[.]githubusercontent[.]com/[^/]+/[^/]+/[0-9a-f]{40}/",
    spec$artifact))
  artifact_path <- testthat::test_path(
    "..", "..", "releases", "m1", "2026-06-26-nar-geonames-centroids",
    "opcc_m1_centroids.csv.gz")
  testthat::skip_if_not(file.exists(artifact_path))
  testthat::expect_equal(
    tolower(digest::digest(artifact_path, algo = "sha256", file = TRUE)),
    tolower(spec$sha256))
})
