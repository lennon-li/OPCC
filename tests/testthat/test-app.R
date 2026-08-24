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

test_that("app loads DA boundaries synchronously, after join validation", {
  app_source <- readLines(system.file("shiny", "app.R", package = "OPCC"))

  # The boundary load previously ran in a future/multisession worker, which
  # could deadlock and freeze Shiny's event loop. It must stay synchronous.
  # Check code only; the file explains the history in comments.
  app_code <- app_source[!grepl("^\\s*#", app_source)]
  expect_false(any(grepl("ExtendedTask", app_code, fixed = TRUE)))
  expect_false(any(grepl("future_promise", app_code, fixed = TRUE)))
  expect_false(any(grepl("multisession", app_code, fixed = TRUE)))

  join_start <- grep("observeEvent\\(input\\$run_join", app_source)[[1]]
  join_block <- app_source[join_start:length(app_source)]
  validation_line <- grep(
    'inherits(result, "error")', join_block, fixed = TRUE
  )[[1]]
  boundary_line <- grep(
    "load_da_simplified(da_simplify_tolerance)", join_block, fixed = TRUE
  )[[1]]
  expect_gt(boundary_line, validation_line)

  # The boundary load must sit inside a progress indicator, so a long load
  # never looks like a frozen app.
  progress_line <- grep("withProgress", join_block, fixed = TRUE)
  expect_true(any(progress_line < boundary_line))
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
  for (pkg in c("shiny", "bslib", "DT", "leaflet")) {
    skip_if_not_installed(pkg)
  }
  app_dir <- system.file("shiny", package = "OPCC")
  # run_app() evaluates the app in a child of OPCC's namespace so app.R can
  # reach package internals without ::: ; the test must load it the same way
  # or it exercises a different scope than users get.
  app_obj <- source(file.path(app_dir, "app.R"),
                    local = new.env(parent = asNamespace("OPCC")))$value
  csv_path <- tempfile(fileext = ".csv")
  on.exit(unlink(csv_path), add = TRUE)
  utils::write.csv(
    data.frame(id = 1:2, `Postal Code` = c("m5v3a8", "M4V 1A1"),
               check.names = FALSE),
    csv_path, row.names = FALSE)
  shiny::testServer(app_obj, {
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

test_that(".postal_points_sf returns one feature per postal code with DA rollup", {
  testthat::skip_if_not_installed("sf")
  points <- data.frame(
    postal_code = c("M5V 3A8", "M4V 1A1", "H0H 0H0"),
    latitude = c(43.64, 43.68, 70.00),
    longitude = c(-79.39, -79.33, -90.00),
    point_source = c("nar_centroid", "nar_centroid", "geonames"),
    point_method = c("nar_address_mean_wgs84", "nar_address_mean_wgs84",
                     "geonames_direct_wgs84"),
    stringsAsFactors = FALSE
  )
  joined <- data.frame(
    opcc_postal_code = c("M5V 3A8", "M5V 3A8", "M4V 1A1"),
    DAUID = c("35204841", "35204842", "35202806"),
    stringsAsFactors = FALSE
  )
  attr(joined, "opcc_postal_code_col") <- "opcc_postal_code"
  attr(joined, "opcc_dauid_col") <- "DAUID"
  out <- OPCC:::.postal_points_sf(points, joined)
  expect_equal(nrow(out), 3L)
  expect_equal(out$pcode, c("M5V 3A8", "M4V 1A1", "H0H 0H0"))
  expect_equal(out$n_da, c(2L, 1L, 0L))
  expect_equal(out$matched, c("Y", "Y", "N"))
  expect_equal(out$dauid[out$pcode == "M5V 3A8"], "35204841,35204842")
  expect_equal(out$dauid[out$pcode == "H0H 0H0"], "")
})

test_that(".postal_points_sf returns an sf object in EPSG:4326 with the expected columns", {
  testthat::skip_if_not_installed("sf")
  points <- data.frame(
    postal_code = "M5V 3A8",
    latitude = 43.64,
    longitude = -79.39,
    point_source = "nar_centroid",
    point_method = "nar_address_mean_wgs84",
    stringsAsFactors = FALSE
  )
  joined <- data.frame(
    opcc_postal_code = "M5V 3A8",
    DAUID = "35204841",
    stringsAsFactors = FALSE
  )
  attr(joined, "opcc_postal_code_col") <- "opcc_postal_code"
  attr(joined, "opcc_dauid_col") <- "DAUID"
  out <- OPCC:::.postal_points_sf(points, joined)
  expect_true(inherits(out, "sf"))
  expect_equal(sf::st_crs(out)$epsg, 4326)
  expect_equal(names(out), c("pcode", "src", "method", "matched", "n_da",
                              "dauid", "geometry"))
})

test_that(".postal_points_sf truncates a very long dauid string for the DBF limit", {
  testthat::skip_if_not_installed("sf")
  dauids <- paste0("3520", sprintf("%04d", seq_len(40)))
  dauids_joined <- paste(sort(dauids), collapse = ",")
  expect_true(nchar(dauids_joined) > 254L)
  points <- data.frame(
    postal_code = "M5V 3A8",
    latitude = 43.64,
    longitude = -79.39,
    point_source = "nar_centroid",
    point_method = "nar_address_mean_wgs84",
    stringsAsFactors = FALSE
  )
  joined <- data.frame(
    opcc_postal_code = rep("M5V 3A8", length(dauids)),
    DAUID = dauids,
    stringsAsFactors = FALSE
  )
  attr(joined, "opcc_postal_code_col") <- "opcc_postal_code"
  attr(joined, "opcc_dauid_col") <- "DAUID"
  out <- OPCC:::.postal_points_sf(points, joined)
  expect_equal(nrow(out), 1L)
  expect_equal(out$n_da, length(dauids))
  expect_equal(nchar(out$dauid), 254L)
  expect_true(grepl("\\.\\.\\.$", out$dauid))
})

test_that(".write_postal_points_shapefile writes a readable zipped shapefile", {
  testthat::skip_if_not_installed("sf")
  points <- data.frame(
    postal_code = c("M5V 3A8", "M4V 1A1"),
    latitude = c(43.64, 43.68),
    longitude = c(-79.39, -79.33),
    point_source = c("nar_centroid", "nar_centroid"),
    point_method = c("nar_address_mean_wgs84", "nar_address_mean_wgs84"),
    stringsAsFactors = FALSE
  )
  joined <- data.frame(
    opcc_postal_code = c("M5V 3A8", "M4V 1A1"),
    DAUID = c("35204841", "35202806"),
    stringsAsFactors = FALSE
  )
  attr(joined, "opcc_postal_code_col") <- "opcc_postal_code"
  attr(joined, "opcc_dauid_col") <- "DAUID"
  sf_points <- OPCC:::.postal_points_sf(points, joined)
  zip <- tempfile(fileext = ".zip")
  on.exit(unlink(zip), add = TRUE)
  OPCC:::.write_postal_points_shapefile(sf_points, zip)
  entries <- utils::unzip(zip, list = TRUE)$Name
  expect_true("opcc_postal_points.shp" %in% entries)
  expect_true("opcc_postal_points.shx" %in% entries)
  expect_true("opcc_postal_points.dbf" %in% entries)
  expect_true("opcc_postal_points.prj" %in% entries)
  expect_false(any(grepl("/", entries, fixed = TRUE)))
  tmpdir <- tempfile("opcc_unzip_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  dir.create(tmpdir, recursive = TRUE, showWarnings = FALSE)
  utils::unzip(zip, exdir = tmpdir)
  read_back <- sf::st_read(file.path(tmpdir, "opcc_postal_points.shp"),
                           quiet = TRUE)
  expect_equal(nrow(read_back), 2L)
  expect_equal(sort(read_back$pcode), c("M4V 1A1", "M5V 3A8"))
})

test_that(".render_opcc_reproducer_script emits the shapefile step for typed codes", {
  script <- OPCC:::.render_opcc_reproducer_script(
    input_file = NULL, postal_col = "postal_code", output_dir = ".",
    vintage = "2026-07-20", all_links = FALSE,
    codes = c("M5V 3A8", "K1A 0B1"))
  expect_match(script, "opcc_postal_points.zip", fixed = TRUE)
  expect_match(script, "OPCC::export_postal_points(", fixed = TRUE)
  # The script is handed to the user, so it must stay on public API.
  expect_false(grepl(":::", paste(script, collapse = ""), fixed = TRUE))
})

test_that(".render_opcc_reproducer_script emits the shapefile step for uploads", {
  script <- OPCC:::.render_opcc_reproducer_script(
    "my records.csv", "Postal Code", ".", "2026-07-20", all_links = FALSE)
  expect_match(script, "opcc_postal_points.zip", fixed = TRUE)
  expect_match(script, "OPCC::export_postal_points(", fixed = TRUE)
  # The script is handed to the user, so it must stay on public API.
  expect_false(grepl(":::", paste(script, collapse = ""), fixed = TRUE))
})

test_that(".render_opcc_reproducer_script shapefile output parses and stays ASCII", {
  typed <- OPCC:::.render_opcc_reproducer_script(
    input_file = NULL, postal_col = "postal_code", output_dir = ".",
    vintage = "2026-07-20", codes = c("M5V 3A8", "K1A 0B1"))
  uploaded <- OPCC:::.render_opcc_reproducer_script(
    "my records.csv", "Postal Code", ".", "2026-07-20")
  for (script in list(typed, uploaded)) {
    expect_true(all(charToRaw(script) < as.raw(128)))
    parsed <- parse(text = script)
    expect_true(length(parsed) > 5L)
    expect_match(script, "opcc_postal_points.zip", fixed = TRUE)
  }
})
