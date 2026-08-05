app_da_fixture <- function() {
  data.frame(
    postal_code = c("M4V 1A1", "M5V 3A8", "M5V 3A8", "P0T 1A0", "P0T 1A0"),
    DAUID = c("35202806", "35204841", "35204842", "35580016", "35580017"),
    allocation_weight = c(1, 0.7, 0.3, 0.6, 0.4),
    n_contributing_dbs = c(1L, 1L, 2L, 3L, 1L),
    contributing_dbuids = c("35202806007", "35204841009", "35204841010|35204841011",
                            "35580016001|35580016002|35580016003", "35580017001"),
    source_vintages = c("2026-06-26", "2026-06-26", "2026-06-26",
                        "2026-06-26", "2026-06-26"),
    census_vintages = c("2021", "2021", "2021", "2021", "2021"),
    evidence_classes = NA_character_,
    best_link = c(TRUE, TRUE, FALSE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
}

test_that(".detect_postal_column prefers name patterns, then content", {
  by_name <- data.frame(id = 1:2, `Postal Code` = c("M5V 3A8", "M4V 1A1"),
                        check.names = FALSE)
  expect_equal(OPCC:::.detect_postal_column(by_name), "Postal Code")

  by_name_variant <- data.frame(record = 1:2, pcode = c("m4v1a1", "m5v3a8"))
  expect_equal(OPCC:::.detect_postal_column(by_name_variant), "pcode")

  by_content <- data.frame(
    facility = c("Site A", "Site B", "Site C", "Site D"),
    location = c("M5V 3A8", "m4v-1a1", "K1A0B1", "P0T 1A0"))
  expect_equal(OPCC:::.detect_postal_column(by_content), "location")

  none <- data.frame(a = c("x", "y"), b = c(1, 2))
  expect_true(is.na(OPCC:::.detect_postal_column(none)))
  expect_true(is.na(OPCC:::.detect_postal_column(data.frame()[, , drop = FALSE])))
})

test_that(".postal_da_join normalizes keys and reports unmatched codes", {
  records <- data.frame(
    id = 1:3,
    pc = c("m5v3a8", "M5V 3A8", "H0H 0H0"),
    stringsAsFactors = FALSE)
  result <- OPCC:::.postal_da_join(records, "pc", app_da_fixture(),
                                   all_links = FALSE)
  expect_equal(result$n_input, 3L)
  expect_equal(result$n_codes, 2L)
  expect_equal(result$unmatched, "H0H 0H0")
  expect_equal(result$invalid_count, 0L)
  joined <- result$joined
  expect_equal(nrow(joined), 3L)
  expect_equal(joined$id, 1:3)
  expect_equal(joined$DAUID[joined$id %in% 1:2], c("35204841", "35204841"))
  expect_true(is.na(joined$DAUID[[3]]))
  expect_true("opcc_postal_code" %in% names(joined))
})

test_that(".postal_da_join counts invalid values separately from unmatched", {
  records <- data.frame(
    id = 1:3,
    pc = c("M5V 3A8", "not a code", NA),
    stringsAsFactors = FALSE)
  result <- OPCC:::.postal_da_join(records, "pc", app_da_fixture())
  expect_equal(result$invalid_count, 1L)
  expect_equal(result$unmatched, character(0))
  expect_true(is.na(result$joined$DAUID[[2]]))
})

test_that(".postal_da_join with all_links fans out only multi-DA codes", {
  records <- data.frame(id = 1:2, pc = c("P0T 1A0", "M5V 3A8"),
                        stringsAsFactors = FALSE)
  result <- OPCC:::.postal_da_join(records, "pc", app_da_fixture(),
                                   all_links = TRUE)
  expect_equal(nrow(result$joined), 4L)
  pot_rows <- result$joined[result$joined$opcc_postal_code == "P0T 1A0", ]
  expect_equal(pot_rows$DAUID, c("35580016", "35580017"))
  m5v_rows <- result$joined[result$joined$opcc_postal_code == "M5V 3A8", ]
  expect_equal(m5v_rows$DAUID, c("35204841", "35204842"))
})

test_that(".postal_da_join preserves interleaved order and reserved columns", {
  records <- data.frame(
    id = 1:4,
    pc = c("M5V 3A8", "P0T 1A0", "M5V 3A8", "P0T 1A0"),
    .opcc_postal_key = paste0("user-key-", 1:4),
    opcc_postal_code = paste0("user-code-", 1:4),
    DAUID = paste0("user-da-", 1:4),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  result <- OPCC:::.postal_da_join(
    records, "pc", app_da_fixture(), all_links = TRUE
  )
  joined <- result$joined
  expect_equal(joined$id, rep(1:4, each = 2L))
  expect_equal(joined$DAUID, rep(records$DAUID, each = 2L))
  expect_equal(result$dauid_col, "opcc_DAUID")
  expect_equal(joined[[result$dauid_col]],
               rep(c("35204841", "35204842",
                     "35580016", "35580017"), 2L))
  expect_equal(joined$.opcc_postal_key,
               rep(records$.opcc_postal_key, each = 2L))
  expect_equal(joined$opcc_postal_code,
               rep(records$opcc_postal_code, each = 2L))
  expect_equal(result$postal_code_col, ".opcc_join_postal_code")
  expect_equal(joined[[result$postal_code_col]], rep(records$pc, each = 2L))
  expect_identical(anyDuplicated(names(joined)), 0L)
})

test_that("DA task state queues only the latest request and rejects stale work", {
  state <- list(current_id = NULL, running_id = NULL, pending = NULL)
  first <- list(id = 1L, dauids = "old")
  second <- list(id = 2L, dauids = "new")
  state <- OPCC:::.da_task_transition(state, "join", first)
  expect_equal(state$invoke, first)
  state$invoke <- NULL
  state <- OPCC:::.da_task_transition(state, "join", second)
  expect_equal(state$running_id, 1L)
  expect_equal(state$pending, second)
  state <- OPCC:::.da_task_transition(state, "finished")
  expect_false(state$accept)
  expect_equal(state$invoke, second)
  state$invoke <- NULL
  state <- OPCC:::.da_task_transition(state, "finished")
  expect_true(state$accept)
})

test_that("DA task invalidation rejects running work and drops queued work", {
  state <- list(current_id = NULL, running_id = NULL, pending = NULL)
  first <- list(id = 1L, dauids = "old")
  second <- list(id = 2L, dauids = "queued")
  state <- OPCC:::.da_task_transition(state, "join", first)
  state$invoke <- NULL
  state <- OPCC:::.da_task_transition(state, "join", second)

  state <- OPCC:::.da_task_transition(state, "invalidate")
  expect_null(state$current_id)
  expect_null(state$pending)
  expect_equal(state$running_id, first$id)

  state <- OPCC:::.da_task_transition(state, "finished")
  expect_false(state$accept)
  expect_null(state$invoke)
})

test_that("app wires upload invalidation after input and valid joins after validation", {
  app_source <- readLines(system.file("shiny", "app.R", package = "OPCC"))
  upload_start <- grep("observeEvent\\(input\\$input_file", app_source)[[1]]
  join_start <- grep("observeEvent\\(input\\$run_join", app_source)[[1]]
  upload_block <- app_source[upload_start:(join_start - 1L)]
  join_block <- app_source[join_start:length(app_source)]

  expect_true(any(grepl(
    '.da_task_transition(task_state, "invalidate")',
    upload_block, fixed = TRUE
  )))
  validation_line <- grep(
    'inherits(result, "error")', join_block, fixed = TRUE
  )[[1]]
  valid_join_line <- grep(
    '.da_task_transition(', join_block, fixed = TRUE
  )[[1]]
  expect_gt(valid_join_line, validation_line)
})

test_that(".postal_da_join does not multiply duplicate input rows", {
  records <- data.frame(id = 1:4, pc = rep("m5v3a8", 4),
                        stringsAsFactors = FALSE)
  result <- OPCC:::.postal_da_join(records, "pc", app_da_fixture())
  expect_equal(nrow(result$joined), 4L)
  expect_true(all(result$joined$DAUID == "35204841"))
})

test_that(".postal_da_join rejects an unknown column", {
  records <- data.frame(id = 1, pc = "M5V 3A8", stringsAsFactors = FALSE)
  expect_error(
    OPCC:::.postal_da_join(records, "nope", app_da_fixture()),
    "Unknown postal code column")
})

test_that("app uploads a CSV and auto-detects the postal column offline", {
  for (pkg in c("shiny", "bslib", "DT", "leaflet", "promises", "future")) {
    skip_if_not_installed(pkg)
  }
  app_dir <- system.file("shiny", package = "OPCC")
  csv_path <- tempfile(fileext = ".csv")
  on.exit(unlink(csv_path), add = TRUE)
  utils::write.csv(
    data.frame(id = 1:2, `Postal Code` = c("m5v3a8", "M4V 1A1"),
               check.names = FALSE),
    csv_path, row.names = FALSE)
  shiny::testServer(shiny::shinyAppDir(app_dir), {
    session$setInputs(input_mode = "file")
    session$setInputs(
      input_file = list(datapath = csv_path, name = "records.csv"))
    expect_false(is.null(records_rv()))
    expect_equal(nrow(records_rv()), 2L)
    col_ui <- paste(as.character(output$postal_col_ui), collapse = "")
    expect_match(col_ui, "postal_col", fixed = TRUE)
    expect_match(col_ui, "selected", fixed = TRUE)
    expect_match(col_ui, "Postal Code", fixed = TRUE)
    expect_true(is.null(joined_rv()))
  })
})

test_that(".parse_postal_text splits one postal code per line", {
  expect_equal(
    OPCC:::.parse_postal_text("M5V 3A8\nK1A 0B1\nN6A3K7"),
    c("M5V 3A8", "K1A 0B1", "N6A3K7"))
  expect_equal(
    OPCC:::.parse_postal_text("m5v 3a8\nK1A 0B1\n "),
    c("m5v 3a8", "K1A 0B1"))
  expect_equal(OPCC:::.parse_postal_text("   "), character(0))
  expect_equal(OPCC:::.parse_postal_text("\n  \n"), character(0))
  expect_equal(OPCC:::.parse_postal_text(NULL), character(0))
})

test_that(".postal_centroids filters and coerces a local centroid artifact", {
  gz_path <- tempfile(fileext = ".csv.gz")
  on.exit(unlink(gz_path), add = TRUE)
  con <- gzfile(gz_path, "w")
  utils::write.csv(
    data.frame(
      postal_code = c("M5V 3A8", "K1A 0B1"),
      latitude = c("43.64", "45.42"),
      longitude = c("-79.39", "-75.70"),
      point_source = c("nar_centroid", "geonames"),
      point_method = c("nar_address_mean_wgs84", "geonames_direct_wgs84"),
      stringsAsFactors = FALSE),
    con, row.names = FALSE)
  close(con)
  out <- OPCC:::.postal_centroids(c("m5v3a8", "H0H 0H0"),
                                  centroid_file = gz_path)
  expect_equal(nrow(out), 1L)
  expect_equal(out$postal_code, "M5V 3A8")
  expect_equal(out$latitude, 43.64)
  expect_equal(out$longitude, -79.39)
  expect_equal(attr(out, "unmatched"), "H0H 0H0")
})

test_that(".render_opcc_reproducer_script supports typed postal codes", {
  script <- OPCC:::.render_opcc_reproducer_script(
    input_file = NULL, postal_col = "postal_code", output_dir = ".",
    vintage = "2026-07-20", all_links = TRUE,
    codes = c("M5V 3A8", "K1A 0B1"))
  expect_true(is.character(script) && length(script) == 1L)
  expect_true(all(charToRaw(script) < as.raw(128)))
  parsed <- parse(text = script)
  expect_true(length(parsed) > 5L)
  expect_match(script, 'c("M5V 3A8", "K1A 0B1")', fixed = TRUE)
  expect_match(script, 'postal_col <- "postal_code"', fixed = TRUE)
  expect_match(script, "all_links <- TRUE", fixed = TRUE)
  expect_match(script, "opcc_postal_da.csv", fixed = TRUE)
  expect_match(script, "opcc_map.html", fixed = TRUE)
  expect_false(grepl("read.csv", script, fixed = TRUE))
})

test_that(".render_opcc_reproducer_script emits parseable ASCII code", {
  script <- OPCC:::.render_opcc_reproducer_script(
    "my records.csv", "Postal Code", ".", "2026-07-20", all_links = FALSE)
  expect_true(is.character(script) && length(script) == 1L)
  expect_true(all(charToRaw(script) < as.raw(128)))
  parsed <- parse(text = script)
  expect_true(length(parsed) > 5L)
  expect_match(script, '"my records.csv"', fixed = TRUE)
  expect_match(script, '"Postal Code"', fixed = TRUE)
  expect_match(script, 'vintage <- "2026-07-20"', fixed = TRUE)
  expect_match(script, "all_links <- FALSE", fixed = TRUE)
  expect_match(script, "opcc_postal_da.csv", fixed = TRUE)
  expect_match(script, "opcc_map.html", fixed = TRUE)
  expect_match(script, "download_da_boundaries()", fixed = TRUE)
  expect_match(script, "html_escape", fixed = TRUE)
  expect_false(grepl('records[[".opcc_postal_key"]]', script, fixed = TRUE))
  expect_match(script, "source_rows <- rep", fixed = TRUE)
})
