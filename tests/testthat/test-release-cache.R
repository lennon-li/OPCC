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

testthat::test_that("failed downloads cannot poison the final cache and retry", {
  cache <- tempfile("opcc-cache-")
  dir.create(cache)
  on.exit(unlink(cache, recursive = TRUE), add = TRUE)
  destination <- file.path(cache, "artifact.bin")
  writeBin(charToRaw("pre-existing invalid cache"), destination)
  expected <- charToRaw("verified artifact")
  sha256 <- digest::digest(expected, algo = "sha256", serialize = FALSE)

  partial_download <- function(url, destfile, ...) {
    writeBin(charToRaw("partial"), destfile)
    stop("simulated interruption")
  }
  testthat::expect_error(
    OPCC:::.download_verified("unused", destination, sha256, FALSE,
                              downloader = partial_download),
    "simulated interruption"
  )
  testthat::expect_equal(readBin(destination, "raw", n = 1000L),
                         charToRaw("pre-existing invalid cache"))
  testthat::expect_length(list.files(cache, all.files = TRUE,
                                     pattern = "artifact[.]bin[.]"), 0L)

  valid_download <- function(url, destfile, ...) writeBin(expected, destfile)
  testthat::expect_equal(
    OPCC:::.download_verified("unused", destination, sha256, FALSE,
                              downloader = valid_download),
    destination
  )
  testthat::expect_equal(readBin(destination, "raw", n = 1000L), expected)
})

testthat::test_that("invalid temporary payload is removed without replacement", {
  cache <- tempfile("opcc-cache-")
  dir.create(cache)
  on.exit(unlink(cache, recursive = TRUE), add = TRUE)
  destination <- file.path(cache, "artifact.bin")
  expected <- charToRaw("verified artifact")
  sha256 <- digest::digest(expected, algo = "sha256", serialize = FALSE)
  invalid_download <- function(url, destfile, ...) {
    writeBin(charToRaw("wrong payload"), destfile)
  }
  testthat::expect_error(
    OPCC:::.download_verified("unused", destination, sha256, FALSE,
                              downloader = invalid_download),
    "Checksum verification failed"
  )
  testthat::expect_false(file.exists(destination))
  testthat::expect_equal(setdiff(list.files(cache, all.files = TRUE), c(".", "..")),
                         character())
})

testthat::test_that("DA index exposes an immutable verified release", {
  spec <- OPCC:::.release_spec(OPCC:::.da_index(), "2026-06-26")
  testthat::expect_match(spec$artifact, "/c9ce50444328e8f8c659e41d72658c0035bb9603/")
  testthat::expect_match(spec$sha256, "^[0-9a-f]{64}$")
  testthat::expect_match(spec$manifest_sha256, "^[0-9a-f]{64}$")
})
