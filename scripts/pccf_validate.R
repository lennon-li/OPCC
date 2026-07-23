# scripts/pccf_validate.R
#
# Compare checksum-verified OPCC M1, M2, and M5 releases with a local,
# authorised Ontario PCCF extract. Restricted rows stay in memory and all
# outputs are aggregate-only private review artifacts outside the repository.
#
# ASCII-ONLY. No licensed row-level data is copied or redistributed.

library(digest)
library(jsonlite)
library(readr)
library(dplyr)

command_args <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", command_args, value = TRUE)
if (length(script_arg) > 0L) {
  script_path <- normalizePath(
    sub("^--file=", "", script_arg[1]),
    mustWork = TRUE
  )
  repo_root <- dirname(dirname(script_path))
} else {
  candidate <- normalizePath(getwd(), mustWork = TRUE)
  repeat {
    if (file.exists(file.path(candidate, "R", "validation-metrics.R"))) {
      repo_root <- candidate
      break
    }
    parent <- dirname(candidate)
    if (identical(parent, candidate)) {
      stop("Cannot locate the OPCC repository root")
    }
    candidate <- parent
  }
}
source(file.path(repo_root, "R", "validation-metrics.R"))

pccf_parse_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  sli_parse_pccf_args(args)
}

pccf_prepare_centroids <- function(x) {
  required <- c("postal_code", "latitude", "longitude", "point_source")
  missing <- setdiff(required, names(x))
  if (length(missing) > 0L) {
    stop("M1 artifact is missing: ", paste(missing, collapse = ", "))
  }
  result <- x |>
    dplyr::transmute(
      postal_code = sli_normalize_postal_code(postal_code),
      latitude = suppressWarnings(as.numeric(latitude)),
      longitude = suppressWarnings(as.numeric(longitude)),
      point_source = as.character(point_source)
    ) |>
    dplyr::filter(!is.na(latitude), !is.na(longitude)) |>
    dplyr::distinct()
  if (nrow(result) == 0L) {
    stop("M1 artifact contains no usable centroid rows")
  }
  result
}

pccf_run <- function(inputs) {
  sli_validate_output_directory(
    inputs$output_dir,
    repo_root,
    synthetic = FALSE
  )
  if (dir.exists(inputs$output_dir)) {
    stop("Private validation output directory must not already exist")
  }
  release_id_pattern <- "^[A-Za-z0-9][A-Za-z0-9._-]*$"
  if (!grepl(release_id_pattern, inputs$m2_release_id) ||
      !grepl(release_id_pattern, inputs$m5_release_id)) {
    stop("M2 and M5 release IDs are invalid")
  }
  sli_validate_private_input(inputs$pccf_csv, repo_root)
  if (!file.exists(inputs$pccf_contract)) {
    stop("PCCF contract does not exist")
  }
  contract <- tryCatch(
    sli_validate_pccf_contract(
      jsonlite::read_json(inputs$pccf_contract)
    ),
    error = function(error) {
      stop("PCCF contract could not be read or validated", call. = FALSE)
    }
  )

  paths <- list(
    m1_manifest = file.path(
      inputs$m1_release_dir,
      "m1_manifest.json"
    ),
    m1_artifact = file.path(
      inputs$m1_release_dir,
      "opcc_m1_centroids.csv.gz"
    ),
    m2_manifest = file.path(
      repo_root,
      "releases", "m2", inputs$m2_release_id,
      "m2_manifest.json"
    ),
    m2_artifact = file.path(
      repo_root,
      "releases", "m2", inputs$m2_release_id,
      "opcc_m2_correspondence.csv.gz"
    ),
    m5_manifest = file.path(
      repo_root,
      "releases", "m5", inputs$m5_release_id,
      "m5_manifest.json"
    ),
    m5_artifact = file.path(
      repo_root,
      "releases", "m5", inputs$m5_release_id,
      "opcc_m5_da_correspondence.csv.gz"
    )
  )
  if (any(!vapply(paths, file.exists, logical(1)))) {
    stop("One or more selected OPCC release files do not exist")
  }
  manifests <- list(
    m1 = jsonlite::read_json(paths$m1_manifest),
    m2 = jsonlite::read_json(paths$m2_manifest),
    m5 = jsonlite::read_json(paths$m5_manifest)
  )
  release_index_path <- file.path(
    repo_root,
    "inst",
    "extdata",
    "release-index.json"
  )
  if (!file.exists(release_index_path)) {
    stop("Canonical release index does not exist")
  }
  release_index <- jsonlite::read_json(release_index_path)
  sli_verify_indexed_release(
    release_index,
    "m2",
    inputs$m2_release_id,
    paths$m2_artifact,
    paths$m2_manifest
  )
  sli_verify_indexed_release(
    release_index,
    "m5",
    inputs$m5_release_id,
    paths$m5_artifact,
    paths$m5_manifest
  )
  sli_validate_release_lineage(
    manifests$m1,
    manifests$m2,
    paths$m2_artifact,
    paths$m2_manifest,
    manifests$m5,
    contract$census_vintage
  )
  if (!identical(manifests$m1$release_type, "m1_centroids") ||
      !identical(as.integer(manifests$m1$manifest_version), 2L) ||
      !identical(
        basename(paths$m1_artifact),
        manifests$m1$artifact$file
      ) ||
      !identical(
        as.numeric(file.info(paths$m1_artifact)$size),
        as.numeric(manifests$m1$artifact$gz_size_bytes)
      )) {
    stop("M1 release manifest contract mismatch")
  }

  m1 <- sli_verify_m1_artifact(paths$m1_artifact, manifests$m1)
  m2 <- sli_verify_link_artifact(
    paths$m2_artifact,
    manifests$m2,
    level = "DB"
  )
  m5 <- sli_verify_link_artifact(
    paths$m5_artifact,
    manifests$m5,
    level = "DA"
  )
  reference <- sli_read_pccf_reference(inputs$pccf_csv, contract)
  build_ref <- sli_validate_producer_ref(
    inputs$producer_ref,
    c("scripts/pccf_validate.R", "R/validation-metrics.R")
  )

  metrics <- sli_compute_pccf_metrics(
    pccf_prepare_centroids(m1),
    m2,
    m5,
    reference
  )
  releases <- list(
    m1 = sli_build_release_binding(
      manifests$m1,
      paths$m1_manifest,
      paths$m1_artifact,
      "M1",
      basename(inputs$m1_release_dir)
    ),
    m2 = sli_build_release_binding(
      manifests$m2,
      paths$m2_manifest,
      paths$m2_artifact,
      "M2",
      inputs$m2_release_id
    ),
    m5 = sli_build_release_binding(
      manifests$m5,
      paths$m5_manifest,
      paths$m5_artifact,
      "M5",
      inputs$m5_release_id
    )
  )
  result <- list(
    schema_version = 1L,
    mode = "licensed_private",
    build_ref = build_ref,
    pccf = list(
      product = contract$product,
      product_vintage = contract$product_vintage,
      census_vintage = contract$census_vintage,
      province_uid = contract$province_uid,
      coordinate_crs = contract$coordinate_crs,
      point_semantics = contract$point_semantics,
      sha256 = sli_digest_private_file(inputs$pccf_csv),
      raw_rows = reference$row_count,
      distinct_codes = dplyr::n_distinct(
        reference$points$postal_code
      ),
      distinct_points = nrow(reference$points),
      exact_duplicate_rows = reference$exact_duplicate_rows,
      distinct_db_links = nrow(reference$db_links),
      distinct_da_links = nrow(reference$da_links)
    ),
    releases = releases,
    release_index_sha256 = digest::digest(
      release_index_path,
      "sha256",
      file = TRUE
    ),
    metrics = metrics
  )
  sli_validate_aggregate_output(result)

  sli_write_pccf_outputs(result, inputs$output_dir)
  invisible(result)
}

main <- function() {
  Sys.setenv(LANGUAGE = "en")
  inputs <- pccf_parse_args()
  pccf_run(inputs)
  cat("Private aggregate PCCF validation completed.\n")
}

if (sys.nframe() == 0L) {
  main()
}
