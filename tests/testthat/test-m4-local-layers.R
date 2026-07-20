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
