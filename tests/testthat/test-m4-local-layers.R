testthat::test_that("local source layers are normalized and source-separated", {
  adapter <- NULL
  testthat::expect_message(
    adapter <- new_source_adapter(
      "municipal_demo", "Open Government Licence", "municipal address registry",
      schema_map = list(postal_code = "pc")
    ),
    "remains local"
  )
  data <- data.frame(
    pc = c("k1a0a6", "K1A 0A7"), latitude = c(45.4, 45.5),
    longitude = c(-75.7, -75.8), stringsAsFactors = FALSE
  )
  layer <- NULL
  testthat::expect_message(layer <- build_source_layer(data, adapter), "remains local")
  testthat::expect_s3_class(layer, "opcc_source_layer")
  testthat::expect_equal(layer$postal_code, c("K1A 0A6", "K1A 0A7"))
  testthat::expect_equal(unique(layer$source_id), "municipal_demo")
  testthat::expect_match(attr(layer, "opcc_source"), "not a canonical")
})

testthat::test_that("local source data rejects malformed and restricted evidence", {
  adapter <- suppressMessages(new_source_adapter(
    "municipal_demo", "Open Government Licence", "municipal address registry"
  ))
  testthat::expect_error(
    suppressMessages(validate_source_data(data.frame(postal_code = "not-a-code"), adapter)),
    "Invalid"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter("pccf_copy", "open", "PCCF extract")),
    "cannot enter"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter("canada-post-copy", "open", "address extract")),
    "cannot enter"
  )
  testthat::expect_error(
    suppressMessages(validate_source_data(data.frame(postal_code = "K1A 0A6", latitude = 45), adapter)),
    "together"
  )
  testthat::expect_error(
    suppressMessages(validate_source_data(data.frame(
      postal_code = "K1A 0A6", latitude = 91, longitude = -75
    ), adapter)),
    "bounds"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter(
      "municipal_demo", "Open Government Licence", "municipal registry", checksum = "abc"
    )),
    "SHA-256"
  )
})

testthat::test_that("packaged GeoNames adapter carries source-specific provenance", {
  adapter <- NULL
  testthat::expect_message(adapter <- geonames_supplementary_adapter(), "remains local")
  testthat::expect_equal(adapter$source_id, "geonames_ca")
  testthat::expect_equal(adapter$checksum, "b3edbab3aee3c4fbcac004d978fa2635e83cdad0abada1f4e44f02e7cc36cbfa")
  testthat::expect_equal(adapter$schema_map$postal_code, "postal_code")
})

testthat::test_that("profiles and bundles expose reproducible contribution evidence", {
  adapter <- suppressMessages(new_source_adapter(
    "municipal_demo", "Open Government Licence", "municipal address registry",
    retrieval_date = "2026-07-19"
  ))
  layer <- suppressMessages(build_source_layer(data.frame(
    postal_code = c("K1A 0A6", "K1A 0A7", "K1A 0A6"),
    address = c("one", "two", "three"), stringsAsFactors = FALSE
  ), adapter))
  profile <- NULL
  testthat::expect_message(profile <- profile_source_layer(layer), "remains local")
  testthat::expect_equal(profile$rows, 3)
  testthat::expect_equal(profile$postal_codes, 2)
  testthat::expect_equal(profile$duplicate_postal_codes, 1)
  output <- tempfile("opcc-m4-")
  bundle <- NULL
  testthat::expect_message(
    bundle <- contribution_bundle(layer, output, fixture_rows = 2),
    "remains local"
  )
  testthat::expect_s3_class(bundle, "opcc_contribution_bundle")
  testthat::expect_true(all(file.exists(unlist(bundle))))
  provenance <- jsonlite::read_json(bundle$provenance, simplifyVector = TRUE)
  testthat::expect_true(provenance$local_only)
  testthat::expect_false(provenance$canonical_release_modified)
  testthat::expect_equal(nrow(utils::read.csv(bundle$fixture)), 2)
  testthat::expect_error(suppressMessages(contribution_bundle(layer, output)), "already exists")
  testthat::expect_error(suppressMessages(contribution_bundle(layer)), "explicit")
  issue_url <- contribution_issue_url(bundle)
  testthat::expect_match(issue_url, "github.com/lennon-li/OPCC/issues/new")
  testthat::expect_match(issue_url, "source-proposal")
  testthat::expect_message(open_contribution_issue(bundle), "Attach the generated")
  testthat::expect_error(open_contribution_issue(bundle, open = TRUE), "interactive")
})

testthat::test_that("M4.1 schema_map normalizes all mapped source columns before validation", {
  adapter <- suppressMessages(new_source_adapter(
    "ottawa_open_data", "Open Government Licence - City of Ottawa",
    "synthetic Ottawa-style address points",
    schema_map = list(
      postal_code = "POSTAL_CODE",
      latitude = "POINT_Y",
      longitude = "POINT_X",
      address = "ADDRESS",
      source_record_id = "OBJECTID",
      municipality = "MUNICIPALITY",
      source_vintage = "SOURCE_DATE"
    )
  ))
  src <- utils::read.csv(
    testthat::test_path("fixtures", "ottawa-like-source.csv"),
    stringsAsFactors = FALSE
  )
  valid_src <- src[1:3, ]
  layer <- suppressMessages(build_source_layer(valid_src, adapter))
  testthat::expect_true(all(
    c("postal_code", "latitude", "longitude", "address",
      "source_record_id", "municipality", "source_vintage") %in% names(layer)
  ))
  testthat::expect_equal(layer$latitude, c(45.4215, 45.4130, 45.4064))
  testthat::expect_equal(layer$longitude, c(-75.6972, -75.7016, -75.7189))
  testthat::expect_equal(layer$address, c("110 Laurier Ave W", "240 Sparks St", "1 Wellington St"))
  testthat::expect_equal(layer$source_record_id, c(1L, 2L, 3L))
  testthat::expect_equal(layer$municipality, c("Ottawa", "Ottawa", "Ottawa"))
  testthat::expect_equal(layer$source_vintage, c("2026-01-15", "2026-01-15", "2026-01-15"))
})

testthat::test_that("M4.1 on_invalid='error' rejects a source containing malformed rows", {
  adapter <- suppressMessages(new_source_adapter(
    "ottawa_open_data", "Open Government Licence - City of Ottawa",
    "synthetic Ottawa-style address points",
    schema_map = list(
      postal_code = "POSTAL_CODE",
      latitude = "POINT_Y",
      longitude = "POINT_X",
      address = "ADDRESS",
      source_record_id = "OBJECTID",
      municipality = "MUNICIPALITY",
      source_vintage = "SOURCE_DATE"
    )
  ))
  src <- utils::read.csv(
    testthat::test_path("fixtures", "ottawa-like-source.csv"),
    stringsAsFactors = FALSE
  )
  testthat::expect_error(
    suppressMessages(build_source_layer(src, adapter, on_invalid = "error")),
    "Invalid"
  )
})

testthat::test_that("M4.1 on_invalid='drop' returns accepted rows only", {
  adapter <- suppressMessages(new_source_adapter(
    "ottawa_open_data", "Open Government Licence - City of Ottawa",
    "synthetic Ottawa-style address points",
    schema_map = list(
      postal_code = "POSTAL_CODE",
      latitude = "POINT_Y",
      longitude = "POINT_X",
      address = "ADDRESS",
      source_record_id = "OBJECTID",
      municipality = "MUNICIPALITY",
      source_vintage = "SOURCE_DATE"
    )
  ))
  src <- utils::read.csv(
    testthat::test_path("fixtures", "ottawa-like-source.csv"),
    stringsAsFactors = FALSE
  )
  layer <- suppressMessages(build_source_layer(src, adapter, on_invalid = "drop"))
  testthat::expect_s3_class(layer, "opcc_source_layer")
  testthat::expect_equal(nrow(layer), 3L)
  testthat::expect_equal(layer$postal_code, c("K1A 0A6", "K2P 1J4", "K1R 7S8"))
})

testthat::test_that("M4.1 on_invalid='quarantine' retains invalid rows separately", {
  adapter <- suppressMessages(new_source_adapter(
    "ottawa_open_data", "Open Government Licence - City of Ottawa",
    "synthetic Ottawa-style address points",
    schema_map = list(
      postal_code = "POSTAL_CODE",
      latitude = "POINT_Y",
      longitude = "POINT_X",
      address = "ADDRESS",
      source_record_id = "OBJECTID",
      municipality = "MUNICIPALITY",
      source_vintage = "SOURCE_DATE"
    )
  ))
  src <- utils::read.csv(
    testthat::test_path("fixtures", "ottawa-like-source.csv"),
    stringsAsFactors = FALSE
  )
  layer <- suppressMessages(build_source_layer(src, adapter, on_invalid = "quarantine"))
  testthat::expect_s3_class(layer, "opcc_source_layer")
  testthat::expect_equal(nrow(layer), 3L)
  quarantine <- attr(layer, "opcc_quarantine")
  testthat::expect_false(is.null(quarantine))
  testthat::expect_true(nrow(quarantine) >= 3L)
})

testthat::test_that("M4.1 validation report records row-level quality counts", {
  adapter <- suppressMessages(new_source_adapter(
    "ottawa_open_data", "Open Government Licence - City of Ottawa",
    "synthetic Ottawa-style address points",
    schema_map = list(
      postal_code = "POSTAL_CODE",
      latitude = "POINT_Y",
      longitude = "POINT_X",
      address = "ADDRESS",
      source_record_id = "OBJECTID",
      municipality = "MUNICIPALITY",
      source_vintage = "SOURCE_DATE"
    )
  ))
  src <- utils::read.csv(
    testthat::test_path("fixtures", "ottawa-like-source.csv"),
    stringsAsFactors = FALSE
  )
  layer <- suppressMessages(build_source_layer(src, adapter, on_invalid = "drop"))
  report <- attr(layer, "opcc_validation_report")
  testthat::expect_false(is.null(report))
  testthat::expect_equal(report$input_rows, 7L)
  testthat::expect_equal(report$accepted_rows, 3L)
  testthat::expect_equal(report$rejected_rows, 4L)
  testthat::expect_equal(report$invalid_postal_rows, 1L)
  testthat::expect_equal(report$missing_postal_rows, 1L)
  testthat::expect_equal(report$invalid_coordinate_rows, 1L)
  testthat::expect_equal(report$duplicate_evidence_rows, 1L)
})

testthat::test_that("M4.1 backward compatibility: postal_code-only schema_map still works", {
  adapter <- suppressMessages(new_source_adapter(
    "municipal_demo", "Open Government Licence", "municipal address registry",
    schema_map = list(postal_code = "pc")
  ))
  data <- data.frame(
    pc = c("k1a0a6", "K1A 0A7"), latitude = c(45.4, 45.5),
    longitude = c(-75.7, -75.8), stringsAsFactors = FALSE
  )
  layer <- suppressMessages(build_source_layer(data, adapter))
  testthat::expect_s3_class(layer, "opcc_source_layer")
  testthat::expect_equal(layer$postal_code, c("K1A 0A6", "K1A 0A7"))
  testthat::expect_equal(layer$latitude, c(45.4, 45.5))
  testthat::expect_equal(layer$longitude, c(-75.7, -75.8))
})

testthat::test_that("M4.1 schema_map is a validated extensible contract", {
  adapter <- suppressMessages(new_source_adapter(
    "extended_demo", "Open Government Licence", "synthetic registry",
    schema_map = list(postal_code = "POSTAL", accuracy = "ACCURACY")
  ))
  out <- suppressMessages(validate_source_data(
    data.frame(POSTAL = "K1A 0A6", ACCURACY = 4L),
    adapter
  ))
  testthat::expect_equal(out$accuracy, 4L)
  testthat::expect_error(
    suppressMessages(validate_source_data(
      data.frame(POSTAL = "K1A 0A6"),
      adapter
    )),
    "missing mapped source field"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter(
      "bad_map", "Open Government Licence", "synthetic registry",
      schema_map = list(postal_code = c("POSTAL", "OTHER"))
    )),
    "scalar"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter(
      "bad_map", "Open Government Licence", "synthetic registry",
      schema_map = structure(list("POSTAL", "POSTAL"), names = c("postal_code", "address"))
    )),
    "unique source fields"
  )
})

testthat::test_that("M4.1 adapter and row-validation errors are actionable", {
  testthat::expect_error(
    suppressMessages(new_source_adapter("", "open", "synthetic registry")),
    "non-missing scalar"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter("Bad Source", "open", "synthetic registry")),
    "lower-case"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter(
      "bad_map", "open", "synthetic registry",
      schema_map = list(address = "ADDRESS")
    )),
    "containing postal_code"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter(
      "bad_map", "open", "synthetic registry",
      schema_map = structure(list("POSTAL", "ADDRESS"), names = c("postal_code", ""))
    )),
    "canonical field names"
  )
  testthat::expect_error(
    suppressMessages(new_source_adapter(
      "bad_date", "open", "synthetic registry",
      retrieval_date = "not-a-date"
    )),
    "valid date"
  )

  adapter <- suppressMessages(new_source_adapter(
    "row_errors", "open", "synthetic registry"
  ))
  testthat::expect_error(
    suppressMessages(validate_source_data("not a data frame", adapter)),
    "data frame"
  )
  testthat::expect_error(
    suppressMessages(validate_source_data(
      data.frame(postal_code = "K1A 0A6"),
      list()
    )),
    "created by new_source_adapter"
  )
  restricted_adapter <- adapter
  restricted_adapter$lineage <- "PCCF extract"
  testthat::expect_error(
    suppressMessages(validate_source_data(
      data.frame(postal_code = "K1A 0A6"),
      restricted_adapter
    )),
    "cannot enter OPCC"
  )
  testthat::expect_error(
    suppressMessages(validate_source_data(data.frame(
      postal_code = "K1A 0A6",
      latitude = 45,
      longitude = NA_real_
    ), adapter)),
    "supplied together"
  )
  testthat::expect_error(
    suppressMessages(validate_source_data(data.frame(
      postal_code = "K1A 0A6",
      latitude = "not-a-number",
      longitude = -75
    ), adapter)),
    "finite numeric"
  )
})
