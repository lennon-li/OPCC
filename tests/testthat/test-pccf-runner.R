test_that("PCCF reader preserves rows and validates its schema", {
  path <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(
    PC = c("K1A0B1", "K1A 0B1", "M5V 3A8"),
    LAT = c("45.4200", "45.4300", "43.6400"),
    LONG = c("-75.7000", "-75.7100", "-79.3900"),
    DBUID = c("35010001001", "35010001002", "35200001001"),
    DAUID = c("35010001", "35010001", "35200001")
  ), path, row.names = FALSE)

  result <- sli_read_pccf_reference(path)

  expect_equal(nrow(result$points), 3)
  expect_equal(nrow(result$db_links), 3)
  expect_equal(nrow(result$da_links), 2)
  expect_equal(sum(result$points$postal_code == "K1A 0B1"), 2)
  expect_type(result$db_links$DBUID, "character")
  expect_type(result$da_links$DAUID, "character")
})

test_that("PCCF reader rejects unsafe or inconsistent rows", {
  missing <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(
    PC = "K1A 0B1",
    LAT = "45.42",
    LONG = "-75.70"
  ), missing, row.names = FALSE)
  expect_error(
    sli_read_pccf_reference(missing),
    "DBUID.*DAUID"
  )

  inconsistent <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(
    PC = "K1A 0B1",
    LAT = "45.42",
    LONG = "-75.70",
    DBUID = "35010001001",
    DAUID = "35200001"
  ), inconsistent, row.names = FALSE)
  expect_error(
    sli_read_pccf_reference(inconsistent),
    "DBUID.*DAUID"
  )

  outside <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(
    PC = "K1A 0B1",
    LAT = "0",
    LONG = "0",
    DBUID = "35010001001",
    DAUID = "35010001"
  ), outside, row.names = FALSE)
  expect_error(
    sli_read_pccf_reference(outside),
    "Ontario coordinate bounds"
  )
})

test_that("PCCF identity metadata is explicit and path-free", {
  expect_equal(
    sli_validate_pccf_identity("PCCF 2025 QA", "2025-11"),
    list(label = "PCCF 2025 QA", vintage = "2025-11")
  )
  expect_error(
    sli_validate_pccf_identity("/restricted/pccf.csv", "2025-11"),
    "label"
  )
  expect_error(
    sli_validate_pccf_identity("PCCF QA", "latest"),
    "vintage"
  )
})

test_that("M2 and M5 artifacts are verified before use", {
  source <- withr::local_tempfile(fileext = ".csv")
  writeLines(
    c(
      "postal_code,DBUID,best_link",
      "K1A 0B1,35010001001,TRUE"
    ),
    source
  )
  artifact <- withr::local_tempfile(fileext = ".csv.gz")
  input <- file(source, "rb")
  output <- gzfile(artifact, "wb")
  on.exit(try(close(input), silent = TRUE), add = TRUE)
  on.exit(try(close(output), silent = TRUE), add = TRUE)
  writeBin(readBin(input, raw(), file.info(source)$size), output)
  close(input)
  close(output)

  manifest <- list(
    source_vintage = "2026-06-26",
    census_vintage = "2021",
    row_counts = list(correspondence_rows = 1L),
    release_artifact = list(
      sha256 = digest::digest(artifact, "sha256", file = TRUE),
      uncompressed_sha256 = digest::digest(source, "sha256", file = TRUE)
    )
  )

  result <- sli_verify_link_artifact(
    artifact,
    manifest,
    level = "DB"
  )
  expect_equal(nrow(result), 1)

  manifest$release_artifact$sha256 <- paste(rep("0", 64), collapse = "")
  expect_error(
    sli_verify_link_artifact(artifact, manifest, level = "DB"),
    "gzip hash mismatch"
  )
})

test_that("combined PCCF metrics are aggregate-only", {
  centroids <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8", "L0L 1L0", "K0K 1K0"),
    latitude = c(45, 45, 44, 45),
    longitude = c(-75, -79, -78, -77),
    point_source = c(
      "nar_centroid", "geonames", "nar_centroid", "nar_centroid"
    )
  )
  opcc_db <- data.frame(
    postal_code = c(
      "K1A 0B1", "K1A 0B1", "M5V 3A8", "L0L 1L0", "K0K 1K0"
    ),
    DBUID = c(
      "35010001001", "35010001009", "35200001003",
      "35400002008", "35600001010"
    ),
    best_link = c(FALSE, TRUE, TRUE, TRUE, TRUE)
  )
  opcc_da <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8", "L0L 1L0", "K0K 1K0"),
    DAUID = c("35010001", "35200001", "35400002", "35600001"),
    best_link = c(TRUE, TRUE, TRUE, TRUE)
  )
  reference <- list(
    points = data.frame(
      postal_code = c(
        "K1A 0B1", "K1A 0B1", "M5V 3A8", "N0G 1A0", "L0L 1L0"
      ),
      latitude = c(45, 46, 44, 43, 44),
      longitude = c(-75, -75, -79, -80, -78)
    ),
    db_links = data.frame(
      postal_code = c(
        "K1A 0B1", "K1A 0B1", "M5V 3A8", "N0G 1A0", "L0L 1L0"
      ),
      DBUID = c(
        "35010001001", "35010001002", "35200001003",
        "35300001004", "35400001005"
      )
    ),
    da_links = data.frame(
      postal_code = c("K1A 0B1", "M5V 3A8", "N0G 1A0", "L0L 1L0"),
      DAUID = c("35010001", "35200001", "35300001", "35400001")
    )
  )

  result <- sli_compute_pccf_metrics(
    centroids,
    opcc_db,
    opcc_da,
    reference
  )
  serialized <- jsonlite::toJSON(result, auto_unbox = TRUE)

  expect_equal(result$point_accuracy$comparisons, 3)
  expect_equal(
    result$point_accuracy$overall$mean_distance_km,
    37.0649755482,
    tolerance = 1e-9
  )
  expect_equal(
    unname(unlist(result$db_accuracy$link_accuracy[
      c("matched_links", "missing_links", "excess_links")
    ])),
    c(2, 2, 2)
  )
  expect_equal(result$db_accuracy$link_accuracy$macro_jaccard, 4 / 9)
  expect_equal(
    result$db_accuracy$link_accuracy$opcc_best_in_reference_rate,
    1 / 3
  )
  expect_equal(
    unname(unlist(result$da_accuracy$link_accuracy[
      c("matched_links", "missing_links", "excess_links")
    ])),
    c(2, 1, 1)
  )
  expect_equal(result$da_accuracy$link_accuracy$macro_jaccard, 2 / 3)
  expect_equal(
    result$da_accuracy$link_accuracy$opcc_best_in_reference_rate,
    2 / 3
  )
  expect_false(grepl("K1A 0B1", serialized, fixed = TRUE))
  expect_false(grepl("35010001001", serialized, fixed = TRUE))
  expect_false(grepl("postal_code|DBUID|DAUID|latitude|longitude", serialized))
  expect_invisible(sli_validate_aggregate_output(result))
})

test_that("private writer emits only path-free aggregate artifacts", {
  centroids <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8"),
    latitude = c(45.0000001, 43.6400001),
    longitude = c(-75.7000001, -79.3900001),
    point_source = c("nar_centroid", "geonames")
  )
  opcc_db <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8"),
    DBUID = c("35010001001", "35200001001"),
    best_link = c(TRUE, TRUE)
  )
  opcc_da <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8"),
    DAUID = c("35010001", "35200001"),
    best_link = c(TRUE, TRUE)
  )
  reference <- list(
    points = centroids[c("postal_code", "latitude", "longitude")],
    db_links = opcc_db[c("postal_code", "DBUID")],
    da_links = opcc_da[c("postal_code", "DAUID")]
  )
  metrics <- sli_compute_pccf_metrics(
    centroids,
    opcc_db,
    opcc_da,
    reference
  )
  result <- list(
    schema_version = 1L,
    mode = "licensed_private",
    build_ref = paste(rep("a", 40), collapse = ""),
    pccf = list(
      product = "PCCF",
      product_vintage = "2025-11",
      census_vintage = "2021",
      province_uid = "35",
      coordinate_crs = "EPSG:4326",
      point_semantics = "pccf_representative_point",
      sha256 = paste(rep("b", 64), collapse = ""),
      raw_rows = 2L,
      distinct_codes = 2L,
      distinct_points = 2L,
      exact_duplicate_rows = 0L,
      distinct_db_links = 2L,
      distinct_da_links = 2L
    ),
    releases = list(),
    release_index_sha256 = paste(rep("c", 64), collapse = ""),
    metrics = metrics
  )
  parent <- withr::local_tempdir()
  output_dir <- file.path(parent, "private-output-canary")
  private_input_path <- file.path(parent, "licensed-canary.csv")

  expect_invisible(sli_write_pccf_outputs(result, output_dir))

  expected_names <- c(
    "pccf_validation_manifest.json",
    "pccf_validation_metrics.json",
    "pccf_validation_report.md"
  )
  expect_setequal(list.files(output_dir), expected_names)
  paths <- file.path(output_dir, expected_names)
  output_text <- paste(
    unlist(lapply(paths, readLines, warn = FALSE)),
    collapse = "\n"
  )
  canaries <- c(
    "K1A 0B1", "M5V 3A8", "35010001001", "35200001001",
    "35010001", "35200001", "45.0000001", "-75.7000001",
    output_dir, private_input_path
  )
  expect_false(any(vapply(
    canaries,
    grepl,
    logical(1),
    x = output_text,
    fixed = TRUE
  )))
  manifest <- jsonlite::read_json(paths[1])
  expect_equal(
    manifest$outputs$metrics_sha256,
    digest::digest(paths[2], "sha256", file = TRUE)
  )
  expect_equal(
    manifest$outputs$report_sha256,
    digest::digest(paths[3], "sha256", file = TRUE)
  )
  if (.Platform$OS.type != "windows") {
    expect_equal(
      bitwAnd(as.integer(file.info(output_dir)$mode), 511L),
      448L
    )
  }
})

test_that("aggregate guard rejects row-level fields and values", {
  expect_error(
    sli_validate_aggregate_output(list(postal_code = "K1A 0B1")),
    "restricted field"
  )
  expect_error(
    sli_validate_aggregate_output(list(example = "35010001001")),
    "restricted value"
  )
  expect_error(
    sli_validate_aggregate_output(list(label = "/restricted/pccf.csv")),
    "path-like"
  )
})

test_that("private runner requires every explicit input", {
  flags <- c(
    "--m1-release-dir", "releases/m1/example",
    "--m2-release-id", "2026-06-26",
    "--m5-release-id", "2026-07-20",
    "--pccf-csv", "private.csv",
    "--pccf-contract", "pccf-contract.json",
    "--output-dir", "private-output",
    "--producer-ref", "abc123"
  )

  result <- sli_parse_pccf_args(flags)

  expect_equal(result$m2_release_id, "2026-06-26")
  expect_equal(result$m5_release_id, "2026-07-20")
  expect_error(
    sli_parse_pccf_args(flags[-length(flags)]),
    "Missing value"
  )
  expect_error(
    sli_parse_pccf_args(c(flags, "--unexpected", "value")),
    "Unknown argument"
  )
})

test_that("PCCF contract fixes schema and benchmark semantics", {
  contract <- list(
    schema_version = 1L,
    product = "PCCF",
    product_vintage = "2025-11",
    census_vintage = "2021",
    province_uid = "35",
    coordinate_crs = "EPSG:4326",
    point_semantics = "pccf_representative_point",
    columns = list(
      postal_code = "PC",
      latitude = "LAT",
      longitude = "LONG",
      DBUID = "DBUID",
      DAUID = "DAUID"
    ),
    missing_value_policy = "error",
    duplicate_row_policy = "count_then_deduplicate_exact"
  )

  result <- sli_validate_pccf_contract(contract)

  expect_equal(result$product_vintage, "2025-11")
  contract$coordinate_crs <- "EPSG:3347"
  expect_error(
    sli_validate_pccf_contract(contract),
    "EPSG:4326"
  )
})

test_that("release index and M5 ancestry bind compatible releases", {
  m2_artifact <- withr::local_tempfile(fileext = ".csv.gz")
  m2_path <- withr::local_tempfile(fileext = ".json")
  m5_artifact <- withr::local_tempfile(fileext = ".csv.gz")
  m5_path <- withr::local_tempfile(fileext = ".json")
  writeLines("m2 artifact", m2_artifact)
  writeLines("m5 artifact", m5_artifact)
  m1 <- list(
    sources = list(nar = list(release_date = "2026-06-26"))
  )
  m2 <- list(
    source_vintage = "2026-06-26",
    census_vintage = "2021"
  )
  jsonlite::write_json(m2, m2_path, auto_unbox = TRUE)
  m5 <- list(source_m2 = list(
    artifact_sha256 = digest::digest(
      m2_artifact, "sha256", file = TRUE
    ),
    manifest_sha256 = digest::digest(
      m2_path, "sha256", file = TRUE
    ),
    census_vintage = "2021"
  ))
  jsonlite::write_json(m5, m5_path, auto_unbox = TRUE)
  index <- list(
    m2 = list("2026-06-26" = list(
      sha256 = digest::digest(m2_artifact, "sha256", file = TRUE),
      manifest_sha256 = digest::digest(m2_path, "sha256", file = TRUE)
    )),
    m5 = list("2026-07-20" = list(
      sha256 = digest::digest(m5_artifact, "sha256", file = TRUE),
      manifest_sha256 = digest::digest(m5_path, "sha256", file = TRUE)
    ))
  )

  expect_invisible(sli_verify_indexed_release(
    index, "m2", "2026-06-26", m2_artifact, m2_path
  ))
  expect_invisible(sli_verify_indexed_release(
    index, "m5", "2026-07-20", m5_artifact, m5_path
  ))
  expect_invisible(sli_validate_release_lineage(
    m1,
    m2,
    m2_artifact,
    m2_path,
    m5,
    pccf_census_vintage = "2021"
  ))

  amended <- list(
    source_vintage = list(
      nar = "2026-06-26",
      geonames = "2026-07-17"
    ),
    census_vintage = "2021"
  )
  amended_artifact <- withr::local_tempfile(fileext = ".csv.gz")
  amended_path <- withr::local_tempfile(fileext = ".json")
  writeLines("amended artifact", amended_artifact)
  jsonlite::write_json(amended, amended_path, auto_unbox = TRUE)
  expect_error(
    sli_validate_release_lineage(
      m1,
      amended,
      amended_artifact,
      amended_path,
      m5,
      pccf_census_vintage = "2021"
    ),
    "M5 parent"
  )
})

test_that("licensed PCCF input must resolve outside the repository", {
  repo_root <- withr::local_tempdir()
  in_repo <- file.path(repo_root, "pccf.csv")
  writeLines("restricted", in_repo)
  outside <- withr::local_tempfile(fileext = ".csv")
  writeLines("restricted", outside)

  expect_error(
    sli_validate_private_input(in_repo, repo_root),
    "outside the repository"
  )
  expect_invisible(sli_validate_private_input(outside, repo_root))

  linked <- file.path(dirname(outside), "linked-pccf.csv")
  linked_ok <- file.symlink(in_repo, linked)
  testthat::skip_if_not(linked_ok, "symbolic links are unavailable")
  expect_error(
    sli_validate_private_input(linked, repo_root),
    "outside the repository"
  )
})

test_that("licensed input read errors do not reveal local paths", {
  secret_path <- file.path(
    withr::local_tempdir(),
    "never-log-this-pccf-name.csv"
  )
  error <- tryCatch(
    sli_read_pccf_reference(secret_path),
    error = identity
  )

  expect_s3_class(error, "error")
  expect_false(grepl(secret_path, conditionMessage(error), fixed = TRUE))
})
