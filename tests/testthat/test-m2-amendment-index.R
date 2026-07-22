testthat::test_that("M2 GeoNames amendment is discoverable through the release index", {
  vintages <- list_vintages(level = "DB")
  testthat::expect_true("2026-07-19-geonames-amendment" %in% vintages)
})

testthat::test_that("release_manifest works for the M2 amendment vintage", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  manifest <- release_manifest("2026-07-19-geonames-amendment", level = "DB")
  testthat::expect_true(is.list(manifest))
  testthat::expect_true("release_artifact" %in% names(manifest))
})

testthat::test_that("validate_release passes for the M2 amendment vintage", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  result <- validate_release("2026-07-19-geonames-amendment", level = "DB")
  testthat::expect_true(result)
})

testthat::test_that("M2 amendment artifact checksum matches release index", {
  index_path <- testthat::test_path("..", "..", "inst", "extdata", "release-index.json")
  testthat::skip_if_not(file.exists(index_path))
  index <- jsonlite::read_json(index_path, simplifyVector = FALSE)
  spec <- index$m2[["2026-07-19-geonames-amendment"]]
  testthat::expect_true(!is.null(spec))
  testthat::expect_true(grepl("^https://raw[.]githubusercontent[.]com/[^/]+/[^/]+/[0-9a-f]{40}/", spec$artifact))
  testthat::expect_true(grepl("^https://raw[.]githubusercontent[.]com/[^/]+/[^/]+/[0-9a-f]{40}/", spec$manifest))
})
