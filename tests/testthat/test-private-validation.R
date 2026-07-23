test_that("DB reference links retain many-to-many geography", {
  reference <- data.frame(
    postal_code = c("K1A0B1", "K1A 0B1", "K1A 0B1", "M5V 3A8"),
    DBUID = c(
      "35010001001",
      "35010001001",
      "35010001002",
      "35200001001"
    )
  )

  result <- sli_normalize_link_table(
    reference,
    level = "DB",
    role = "reference"
  )

  expect_equal(nrow(result), 3)
  expect_equal(sum(result$postal_code == "K1A 0B1"), 2)
  expect_named(result, c("postal_code", "geo_id", "best_link"))
})

test_that("many-to-many DB metrics use set agreement", {
  reference <- data.frame(
    postal_code = c(
      "K1A 0B1",
      "M5V 3A8", "M5V 3A8",
      "N0G 1A0", "N0G 1A0",
      "P0L 1C0",
      "L0L 1L0"
    ),
    DBUID = c(
      "35010001001",
      "35200001002", "35200001003",
      "35300001005", "35300001006",
      "35400001007",
      "35500001008"
    )
  )
  opcc <- data.frame(
    postal_code = c(
      "K1A 0B1",
      "M5V 3A8", "M5V 3A8",
      "N0G 1A0", "N0G 1A0",
      "L0L 1L0",
      "K0K 1K0"
    ),
    DBUID = c(
      "35010001001",
      "35200001002", "35200001004",
      "35300001005", "35300001006",
      "35500001009",
      "35600001010"
    ),
    best_link = c(TRUE, FALSE, TRUE, TRUE, FALSE, TRUE, TRUE)
  )

  metrics <- sli_compute_link_metrics(opcc, reference, level = "DB")

  expect_equal(
    unlist(metrics$coverage, use.names = FALSE),
    c(5, 5, 4, 1, 1, 0.8, 0.8)
  )
  expect_equal(metrics$link_accuracy$opcc_links, 6)
  expect_equal(metrics$link_accuracy$reference_links, 6)
  expect_equal(metrics$link_accuracy$matched_links, 4)
  expect_equal(metrics$link_accuracy$missing_links, 2)
  expect_equal(metrics$link_accuracy$excess_links, 2)
  expect_equal(metrics$link_accuracy$pair_precision, 2 / 3)
  expect_equal(metrics$link_accuracy$pair_recall, 2 / 3)
  expect_equal(metrics$link_accuracy$f1, 2 / 3)
  expect_equal(metrics$link_accuracy$micro_jaccard, 0.5)
  expect_equal(metrics$link_accuracy$macro_jaccard, 7 / 12)
  expect_equal(metrics$link_accuracy$any_link_rate, 0.75)
  expect_equal(metrics$link_accuracy$exact_set_rate, 0.5)
  expect_equal(metrics$link_accuracy$opcc_best_in_reference_rate, 0.5)

  single <- metrics$by_reference_cardinality[
    metrics$by_reference_cardinality$reference_cardinality == "single",
  ]
  multiple <- metrics$by_reference_cardinality[
    metrics$by_reference_cardinality$reference_cardinality == "multiple",
  ]
  expect_equal(single$n_codes, 2)
  expect_equal(single$micro_jaccard, 1 / 3)
  expect_equal(multiple$n_codes, 2)
  expect_equal(multiple$micro_jaccard, 0.6)
})

test_that("the same set engine validates DA correspondence", {
  reference <- data.frame(
    postal_code = c("K1A 0B1", "K1A 0B1", "M5V 3A8"),
    DAUID = c("35010001", "35010002", "35200001")
  )
  opcc <- data.frame(
    postal_code = c("K1A 0B1", "K1A 0B1", "M5V 3A8"),
    DAUID = c("35010001", "35010003", "35200001"),
    best_link = c(TRUE, FALSE, TRUE)
  )

  metrics <- sli_compute_link_metrics(opcc, reference, level = "DA")

  expect_identical(metrics$level, "DA")
  expect_equal(metrics$link_accuracy$matched_links, 2)
  expect_equal(metrics$link_accuracy$missing_links, 1)
  expect_equal(metrics$link_accuracy$excess_links, 1)
})

test_that("no shared codes return coverage with undefined accuracy rates", {
  reference <- data.frame(
    postal_code = "K1A 0B1",
    DAUID = "35010001"
  )
  opcc <- data.frame(
    postal_code = "M5V 3A8",
    DAUID = "35200001",
    best_link = TRUE
  )

  metrics <- sli_compute_link_metrics(opcc, reference, level = "DA")

  expect_equal(metrics$coverage$compared_codes, 0)
  expect_equal(metrics$link_accuracy$matched_links, 0)
  expect_true(is.na(metrics$link_accuracy$pair_precision))
  expect_true(is.na(metrics$link_accuracy$pair_recall))
  expect_true(is.na(metrics$link_accuracy$micro_jaccard))
  expect_true(is.na(metrics$link_accuracy$macro_jaccard))
})

test_that("complete link disagreement has zero rather than undefined F1", {
  reference <- data.frame(
    postal_code = "K1A 0B1",
    DAUID = "35010001"
  )
  opcc <- data.frame(
    postal_code = "K1A 0B1",
    DAUID = "35010002",
    best_link = TRUE
  )

  metrics <- sli_compute_link_metrics(opcc, reference, level = "DA")

  expect_equal(metrics$link_accuracy$pair_precision, 0)
  expect_equal(metrics$link_accuracy$pair_recall, 0)
  expect_equal(metrics$link_accuracy$f1, 0)
  expect_equal(metrics$link_accuracy$micro_jaccard, 0)
  expect_equal(metrics$link_accuracy$macro_jaccard, 0)
})

test_that("link validation rejects malformed or ambiguous OPCC inputs", {
  expect_error(
    sli_normalize_link_table(
      data.frame(postal_code = "K1A 0B1", DBUID = 35010001001),
      level = "DB",
      role = "reference"
    ),
    "character"
  )

  duplicate_opcc <- data.frame(
    postal_code = c("K1A 0B1", "K1A 0B1"),
    DBUID = c("35010001001", "35010001001"),
    best_link = c(TRUE, FALSE)
  )
  expect_error(
    sli_normalize_link_table(duplicate_opcc, "DB", "opcc"),
    "duplicate"
  )

  no_best <- data.frame(
    postal_code = c("K1A 0B1", "K1A 0B1"),
    DBUID = c("35010001001", "35010001002"),
    best_link = c(FALSE, FALSE)
  )
  expect_error(
    sli_normalize_link_table(no_best, "DB", "opcc"),
    "exactly one"
  )
})

test_that("aggregate metrics do not contain restricted row values", {
  secret_postal_code <- "K9Z 9Z9"
  secret_dbuid <- "35999999999"
  reference <- data.frame(
    postal_code = secret_postal_code,
    DBUID = secret_dbuid
  )
  opcc <- data.frame(
    postal_code = secret_postal_code,
    DBUID = secret_dbuid,
    best_link = TRUE
  )

  metrics <- sli_compute_link_metrics(opcc, reference, level = "DB")
  serialized <- jsonlite::toJSON(metrics, auto_unbox = TRUE)

  expect_false(grepl(secret_postal_code, serialized, fixed = TRUE))
  expect_false(grepl(secret_dbuid, serialized, fixed = TRUE))
  expect_false(grepl("postal_code", serialized, fixed = TRUE))
  expect_false(grepl("DBUID", serialized, fixed = TRUE))
  expect_false(grepl("DAUID", serialized, fixed = TRUE))
  expect_false(grepl("latitude", serialized, fixed = TRUE))
  expect_false(grepl("longitude", serialized, fixed = TRUE))
})

test_that("licensed validation output cannot target the repository", {
  repo_root <- withr::local_tempdir()
  tracked_output <- file.path(repo_root, "docs")
  dir.create(tracked_output)
  private_output <- withr::local_tempdir()

  expect_error(
    sli_validate_output_directory(
      tracked_output,
      repo_root,
      synthetic = FALSE
    ),
    "outside the repository"
  )
  expect_invisible(
    sli_validate_output_directory(
      tracked_output,
      repo_root,
      synthetic = TRUE
    )
  )
  expect_invisible(
    sli_validate_output_directory(
      private_output,
      repo_root,
      synthetic = FALSE
    )
  )
})

test_that("licensed output rejects a symlink parent into the repository", {
  repo_root <- withr::local_tempdir()
  tracked_output <- file.path(repo_root, "docs")
  dir.create(tracked_output)
  outside <- withr::local_tempdir()
  linked_parent <- file.path(outside, "linked-docs")
  linked <- file.symlink(tracked_output, linked_parent)
  testthat::skip_if_not(linked, "symbolic links are unavailable")

  expect_error(
    sli_validate_output_directory(
      file.path(linked_parent, "private-run"),
      repo_root,
      synthetic = FALSE
    ),
    "outside the repository"
  )
})
