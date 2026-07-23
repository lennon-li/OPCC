# scripts/pccf_da_validate.R
#
# Validate checksum-pinned OPCC M5 postal-code-to-DA correspondence against a
# local authorised PCCF-derived XLSX export. The workbook lacks coordinates
# and DBUID, so this runner explicitly does not validate M1 or M2.
#
# ASCII-ONLY. No licensed row-level data is copied or redistributed.

library(digest)
library(jsonlite)
library(readxl)

command_args <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", command_args, value = TRUE)
script_path <- normalizePath(
  sub("^--file=", "", script_arg[1]),
  mustWork = TRUE
)
repo_root <- dirname(dirname(script_path))
source(file.path(repo_root, "R", "validation-metrics.R"))

pccf_da_run <- function(inputs) {
  sli_validate_output_directory(
    inputs$output_dir,
    repo_root,
    synthetic = FALSE
  )
  if (dir.exists(inputs$output_dir)) {
    stop("Private DA validation output directory must not already exist")
  }
  release_id_pattern <- "^[A-Za-z0-9][A-Za-z0-9._-]*$"
  if (!grepl(release_id_pattern, inputs$m5_release_id)) {
    stop("M5 release ID is invalid")
  }
  sli_validate_private_input(inputs$pccf_xlsx, repo_root)
  if (!file.exists(inputs$pccf_contract)) {
    stop("PCCF DA contract does not exist")
  }
  canonical_contract_path <- file.path(
    repo_root,
    "config",
    "pccf-da-validation-contract.example.json"
  )
  if (!file.exists(canonical_contract_path) ||
      !identical(
        digest::digest(
          inputs$pccf_contract,
          "sha256",
          file = TRUE
        ),
        digest::digest(
          canonical_contract_path,
          "sha256",
          file = TRUE
        )
      )) {
    stop("PCCF DA contract must match the canonical tracked contract")
  }
  contract <- tryCatch(
    sli_validate_pccf_da_contract(
      jsonlite::read_json(inputs$pccf_contract)
    ),
    error = function(error) {
      stop(
        "PCCF DA contract could not be read or validated",
        call. = FALSE
      )
    }
  )

  release_index_path <- file.path(
    repo_root,
    "inst",
    "extdata",
    "release-index.json"
  )
  manifest_path <- file.path(
    repo_root,
    "releases",
    "m5",
    inputs$m5_release_id,
    "m5_manifest.json"
  )
  artifact_path <- file.path(
    repo_root,
    "releases",
    "m5",
    inputs$m5_release_id,
    "opcc_m5_da_correspondence.csv.gz"
  )
  if (!file.exists(release_index_path) ||
      !file.exists(manifest_path) ||
      !file.exists(artifact_path)) {
    stop("Canonical M5 release inputs do not exist")
  }
  release_index <- jsonlite::read_json(release_index_path)
  manifest <- jsonlite::read_json(manifest_path)
  sli_verify_indexed_release(
    release_index,
    "m5",
    inputs$m5_release_id,
    artifact_path,
    manifest_path
  )
  parent_id <- manifest$source_m2$vintage
  parent <- release_index$m2[[parent_id]]
  if (is.null(parent) ||
      !identical(
        parent$sha256,
        manifest$source_m2$artifact_sha256
      ) ||
      !identical(
        parent$manifest_sha256,
        manifest$source_m2$manifest_sha256
      )) {
    stop("M5 parent is not checksum-pinned by the release index")
  }
  if (!identical(
        manifest$source_m2$census_vintage,
        contract$census_vintage
      )) {
    stop("M5 and PCCF DA census vintages do not match")
  }

  opcc <- sli_verify_link_artifact(
    artifact_path,
    manifest,
    level = "DA"
  )
  reference <- sli_read_pccf_da_xlsx(inputs$pccf_xlsx, contract)
  metrics <- sli_compute_link_metrics(
    opcc,
    reference$links,
    level = "DA"
  )
  if (metrics$coverage$compared_codes == 0L) {
    stop("PCCF DA input has no postal codes comparable with M5")
  }
  producer_files <- c(
    "scripts/pccf_da_validate.R",
    "R/validation-metrics.R",
    "config/pccf-da-validation-contract.example.json"
  )
  build_ref <- sli_validate_producer_files(
    inputs$producer_ref,
    producer_files,
    repo_root
  )
  release <- sli_build_release_binding(
    manifest,
    manifest_path,
    artifact_path,
    "M5",
    inputs$m5_release_id
  )
  result <- sli_build_pccf_da_result(
    metrics = metrics,
    build_ref = build_ref,
    reference = list(
      product = contract$product,
      product_vintage = contract$product_vintage,
      census_vintage = contract$census_vintage,
      contract_sha256 = digest::digest(
        canonical_contract_path,
        "sha256",
        file = TRUE
      ),
      sha256 = sli_digest_private_file(inputs$pccf_xlsx),
      raw_rows = reference$raw_rows,
      excluded_invalid_da_rows = reference$excluded_invalid_da_rows,
      exact_duplicate_rows = reference$exact_duplicate_rows,
      distinct_codes = length(unique(reference$links$postal_code)),
      distinct_da_links = nrow(reference$links)
    ),
    release = release,
    release_index_sha256 = digest::digest(
      release_index_path,
      "sha256",
      file = TRUE
    )
  )
  sli_write_pccf_da_outputs(result, inputs$output_dir)
  invisible(result)
}

main <- function() {
  Sys.setenv(LANGUAGE = "en")
  inputs <- sli_parse_pccf_da_args(commandArgs(trailingOnly = TRUE))
  pccf_da_run(inputs)
  cat("Private aggregate PCCF-derived DA validation completed.\n")
}

if (sys.nframe() == 0L) {
  main()
}
