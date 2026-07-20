testthat::test_that("verified cached release works offline", {
  cache <- tempfile("opcc-cache-")
  dir.create(cache)
  spec <- OPCC:::.release_spec(OPCC:::.index(), "2026-06-26")
  destination <- OPCC:::.cache_path("m2", "2026-06-26", cache, ".csv.gz")
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
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

testthat::test_that("DA index exposes an immutable verified release", {
  spec <- OPCC:::.release_spec(OPCC:::.da_index(), "2026-06-26")
  testthat::expect_match(spec$artifact, "/c9ce50444328e8f8c659e41d72658c0035bb9603/")
  testthat::expect_match(spec$sha256, "^[0-9a-f]{64}$")
  testthat::expect_match(spec$manifest_sha256, "^[0-9a-f]{64}$")
})
