script_path <- if (file.exists("scripts/m6_release_controls.R")) {
  "scripts/m6_release_controls.R"
} else {
  file.path("..", "..", "scripts", "m6_release_controls.R")
}
if (!file.exists(script_path)) {
  testthat::test_that("M6 release control tests are source-checkout tests", {
    testthat::skip("M6 release control script is not installed with the runtime package")
  })
} else {
source(script_path)

testthat::test_that("release drift reports added removed and changed keys", {
  prior <- data.frame(postal_code = c("K1A 0A6", "K1A 0A7"), DAUID = c("1", "2"), allocation_weight = c(.6, 1))
  candidate <- data.frame(postal_code = c("K1A 0A6", "K1A 0A8"), DAUID = c("1", "3"), allocation_weight = c(.7, 1))
  report <- release_drift_report(prior, candidate, c("postal_code", "DAUID"))
  testthat::expect_equal(report$added_keys, 1L)
  testthat::expect_equal(report$removed_keys, 1L)
  testthat::expect_equal(report$changed_weight_keys, 1L)
})

testthat::test_that("release audit rejects mutable URLs and checksum drift", {
  testthat::expect_false(is_commit_pinned_raw_url("https://raw.githubusercontent.com/a/b/main/x"))
  testthat::expect_true(is_commit_pinned_raw_url("https://raw.githubusercontent.com/a/b/0123456789abcdef0123456789abcdef01234567/x"))
  root <- testthat::test_path("..", "..")
  testthat::expect_silent(audit_release_index(
    file.path(root, "inst", "extdata", "release-index.json"),
    file.path(root, "releases")
  ))
})
}
