testthat::test_that("verified cached release works offline", {
  cache <- tempfile("opcc-cache-")
  dir.create(cache)
  spec <- OPCC:::.release_spec(OPCC:::.index(), "2026-06-26")
  destination <- OPCC:::.cache_path("m2", "2026-06-26", cache, ".csv.gz")
  dir.create(dirname(destination), recursive = TRUE)
  file.copy(testthat::test_path("fixtures", "geonames-points.csv.gz"), destination)
  old <- digest::digest(destination, algo = "sha256", file = TRUE)
  testthat::expect_false(identical(old, spec$sha256))
  testthat::expect_error(OPCC:::.download_verified(spec$artifact, destination, spec$sha256, TRUE), "Checksum")
  unlink(cache, recursive = TRUE)
})

testthat::test_that("offline cache miss is explicit", {
  testthat::expect_error(
    get_correspondence(cache_dir = tempfile("opcc-empty-"), offline = TRUE),
    "not cached"
  )
})
