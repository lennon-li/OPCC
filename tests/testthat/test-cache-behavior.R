test_that("large downloads require an explicit cache directory", {
  downloads <- list(
    download_nar,
    download_geonames,
    download_census_boundaries,
    download_da_boundaries,
    download_gaf
  )

  for (download in downloads) {
    expect_error(download(), "cache_dir must be supplied explicitly")
  }
})

test_that("large builds require an explicit output directory before work", {
  expect_error(
    build_centroids("missing-nar", "missing-geonames"),
    "output_dir must be supplied explicitly"
  )
  expect_error(
    build_db_assignment("centroids", "province", "db", "gaf"),
    "output_dir must be supplied explicitly"
  )
  expect_error(
    build_m2("nar", "db", "gaf", "rollup"),
    "output_dir must be supplied explicitly"
  )
})

test_that("an explicit cache directory is created and used", {
  cache_dir <- file.path(tempdir(), "opcc-explicit-cache")
  unlink(cache_dir, recursive = TRUE)

  expect_identical(.opcc_build_cache(cache_dir), cache_dir)
  expect_true(dir.exists(cache_dir))
})

test_that("cache directories must be non-empty character scalars", {
  invalid_paths <- list(1, TRUE, factor("cache"))

  for (path in invalid_paths) {
    expect_error(
      .opcc_build_cache(path),
      "cache_dir must be supplied explicitly"
    )
  }
})

test_that("an explicit download cache is used before network access", {
  cache_dir <- file.path(tempdir(), "opcc-explicit-download-cache")
  downloaded <- character()
  local_mocked_bindings(
    .download_cached = function(url, dest, label) {
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      file.create(dest)
      downloaded <<- c(downloaded, dest)
      invisible(dest)
    },
    .extract_zip = function(zip_path, exdir, label) invisible(character()),
    .package = "OPCC"
  )

  boundaries <- download_census_boundaries(cache_dir = cache_dir)

  expect_identical(
    boundaries,
    list(
      province = file.path(cache_dir, "shp", "lpr_000b21a_e.shp"),
      db = file.path(cache_dir, "shp", "ldb_000b21a_e.shp")
    )
  )
  expect_true(all(startsWith(downloaded, cache_dir)))
})

test_that("an explicit build directory is created before input processing", {
  output_dir <- file.path(tempdir(), "opcc-explicit-build-output")
  unlink(output_dir, recursive = TRUE)
  local_mocked_bindings(
    .check_build_deps = function(...) invisible(),
    .package = "OPCC"
  )

  expect_error(
    build_centroids("missing-nar", "missing-geonames", output_dir),
    "No Ontario NAR Location files"
  )
  expect_true(dir.exists(output_dir))
})
