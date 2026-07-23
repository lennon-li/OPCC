test_that("DA-only contract makes the validation scope explicit", {
  contract <- list(
    schema_version = 1L,
    product = "PCCF_DERIVED_EXPORT",
    product_vintage = "2023-03",
    census_vintage = "2021",
    province_uid = "35",
    file_format = "xlsx",
    sheet = "PCCF_ON_Mar2023_ExportTable",
    columns = list(
      postal_code = "POSTAL_CODE",
      DAUID = "DAUID"
    ),
    missing_value_policy = "error",
    invalid_dauid_policy = "exclude_allowlisted_sentinels_with_count",
    allowed_dauid_sentinels = "0",
    duplicate_row_policy = "count_then_deduplicate_exact"
  )

  result <- sli_validate_pccf_da_contract(contract)

  expect_equal(result$product_vintage, "2023-03")
  expect_equal(result$columns$DAUID, "DAUID")

  contract$census_vintage <- "2016"
  expect_error(
    sli_validate_pccf_da_contract(contract),
    "Ontario 2021"
  )
})

test_that("DA-only runner requires explicit private inputs", {
  args <- c(
    "--m5-release-id", "2026-07-20",
    "--pccf-xlsx", "private.xlsx",
    "--pccf-contract", "contract.json",
    "--output-dir", "private-output",
    "--producer-ref", "abc123"
  )

  result <- sli_parse_pccf_da_args(args)

  expect_equal(result$m5_release_id, "2026-07-20")
  expect_equal(result$pccf_xlsx, "private.xlsx")
  expect_error(
    sli_parse_pccf_da_args(args[-length(args)]),
    "Missing value"
  )
})

test_that("producer files must match the attributed commit bytes", {
  repo <- withr::local_tempdir()
  dir.create(file.path(repo, "scripts"))
  tracked <- file.path(repo, "scripts", "runner.R")
  writeLines("value <- 1", tracked)
  expect_equal(
    system2("git", c("-C", repo, "init", "-q")),
    0
  )
  expect_equal(
    system2("git", c("-C", repo, "add", "scripts/runner.R")),
    0
  )
  expect_equal(
    system2(
      "git",
      c(
        "-C", repo,
        "-c", "user.name=OPCC-Tests",
        "-c", "user.email=opcc-tests@example.invalid",
        "commit", "-q", "-m", "fixture"
      )
    ),
    0
  )
  producer_ref <- system2(
    "git",
    c("-C", repo, "rev-parse", "HEAD"),
    stdout = TRUE
  )

  expect_equal(
    sli_validate_producer_files(
      producer_ref,
      "scripts/runner.R",
      repo
    ),
    producer_ref
  )

  writeLines("value <- 2", tracked)
  expect_error(
    sli_validate_producer_files(
      producer_ref,
      "scripts/runner.R",
      repo
    ),
    "do not match"
  )
})

test_that("DA-only tables preserve many-to-many reference links", {
  contract <- list(
    schema_version = 1L,
    product = "PCCF_DERIVED_EXPORT",
    product_vintage = "2023-03",
    census_vintage = "2021",
    province_uid = "35",
    file_format = "xlsx",
    sheet = "Sheet1",
    columns = list(
      postal_code = "POSTAL_CODE",
      DAUID = "DAUID"
    ),
    missing_value_policy = "error",
    invalid_dauid_policy = "exclude_allowlisted_sentinels_with_count",
    allowed_dauid_sentinels = "0",
    duplicate_row_policy = "count_then_deduplicate_exact"
  )
  input <- data.frame(
    POSTAL_CODE = c(
      "K1A0B1", "K1A 0B1", "K1A 0B1", "M5V 3A8", "N0G 1A0"
    ),
    DAUID = c("35010001", "35010001", "35010002", "35200001", "0"),
    stringsAsFactors = FALSE
  )

  result <- sli_normalize_pccf_da_table(input, contract)

  expect_equal(result$raw_rows, 5)
  expect_equal(result$excluded_invalid_da_rows, 1)
  expect_equal(result$exact_duplicate_rows, 1)
  expect_equal(nrow(result$links), 3)
  expect_equal(sum(result$links$postal_code == "K1A 0B1"), 2)
})

test_that("DA-only tables reject missing and malformed fields", {
  contract <- list(
    schema_version = 1L,
    product = "PCCF_DERIVED_EXPORT",
    product_vintage = "2023-03",
    census_vintage = "2021",
    province_uid = "35",
    file_format = "xlsx",
    sheet = "Sheet1",
    columns = list(
      postal_code = "POSTAL_CODE",
      DAUID = "DAUID"
    ),
    missing_value_policy = "error",
    invalid_dauid_policy = "exclude_allowlisted_sentinels_with_count",
    allowed_dauid_sentinels = "0",
    duplicate_row_policy = "count_then_deduplicate_exact"
  )

  expect_error(
    sli_normalize_pccf_da_table(
      data.frame(POSTAL_CODE = "K1A 0B1"),
      contract
    ),
    "required mapped columns"
  )
  expect_error(
    sli_normalize_pccf_da_table(
      data.frame(
        POSTAL_CODE = "K1A 0B1",
        DAUID = "not-an-id"
      ),
      contract
    ),
    "unexpected invalid"
  )
  expect_error(
    sli_normalize_pccf_da_table(
      data.frame(
        POSTAL_CODE = "K1A 0B1",
        DAUID = NA_character_
      ),
      contract
    ),
    "missing DA"
  )
})

test_that("DA-only result records M1 and M2 as unvalidated", {
  opcc <- data.frame(
    postal_code = c("K1A 0B1", "K1A 0B1", "M5V 3A8"),
    DAUID = c("35010001", "35010002", "35200001"),
    best_link = c(TRUE, FALSE, TRUE)
  )
  reference <- data.frame(
    postal_code = c("K1A 0B1", "M5V 3A8"),
    DAUID = c("35010001", "35200001")
  )

  metrics <- sli_compute_link_metrics(opcc, reference, level = "DA")
  result <- sli_build_pccf_da_result(
    metrics = metrics,
    build_ref = paste(rep("a", 40), collapse = ""),
    reference = list(
      product = "PCCF_DERIVED_EXPORT",
      product_vintage = "2023-03",
      census_vintage = "2021",
      contract_sha256 = paste(rep("f", 64), collapse = ""),
      sha256 = paste(rep("b", 64), collapse = ""),
      raw_rows = 2L,
      exact_duplicate_rows = 0L,
      distinct_codes = 2L,
      distinct_da_links = 2L
    ),
    release = list(
      milestone = "M5",
      release_id = "2026-07-20",
      vintage = "2026-06-26",
      census_vintage = "2021",
      manifest_sha256 = paste(rep("c", 64), collapse = ""),
      artifact_sha256 = paste(rep("d", 64), collapse = ""),
      rows = 3L
    ),
    release_index_sha256 = paste(rep("e", 64), collapse = "")
  )

  expect_equal(result$scope$validated_milestones, "M5")
  expect_equal(result$scope$unvalidated_milestones, c("M1", "M2"))
  expect_match(result$reference$contract_sha256, "^[a-f0-9]{64}$")
  expect_equal(result$metrics$link_accuracy$any_link_rate, 1)
  expect_invisible(sli_validate_aggregate_output(result))
})

test_that("DA-only writer emits aggregate files without row canaries", {
  opcc <- data.frame(
    postal_code = "K1A 0B1",
    DAUID = "35010001",
    best_link = TRUE
  )
  reference <- data.frame(
    postal_code = "K1A 0B1",
    DAUID = "35010001"
  )
  result <- sli_build_pccf_da_result(
    metrics = sli_compute_link_metrics(opcc, reference, "DA"),
    build_ref = paste(rep("a", 40), collapse = ""),
    reference = list(
      product = "PCCF_DERIVED_EXPORT",
      product_vintage = "2023-03",
      census_vintage = "2021",
      contract_sha256 = paste(rep("f", 64), collapse = ""),
      sha256 = paste(rep("b", 64), collapse = ""),
      raw_rows = 1L,
      exact_duplicate_rows = 0L,
      distinct_codes = 1L,
      distinct_da_links = 1L
    ),
    release = list(
      milestone = "M5",
      release_id = "2026-07-20",
      vintage = "2026-06-26",
      census_vintage = "2021",
      manifest_sha256 = paste(rep("c", 64), collapse = ""),
      artifact_sha256 = paste(rep("d", 64), collapse = ""),
      rows = 1L
    ),
    release_index_sha256 = paste(rep("e", 64), collapse = "")
  )
  parent <- withr::local_tempdir()
  output_dir <- file.path(parent, "private-da-output")

  expect_invisible(sli_write_pccf_da_outputs(result, output_dir))

  expected <- c(
    "pccf_da_validation_manifest.json",
    "pccf_da_validation_metrics.json",
    "pccf_da_validation_report.md"
  )
  expect_setequal(list.files(output_dir), expected)
  output_text <- paste(
    unlist(lapply(
      file.path(output_dir, expected),
      readLines,
      warn = FALSE
    )),
    collapse = "\n"
  )
  expect_false(grepl("K1A 0B1", output_text, fixed = TRUE))
  expect_false(grepl("35010001", output_text, fixed = TRUE))
  expect_false(grepl(output_dir, output_text, fixed = TRUE))
})
