#!/usr/bin/env Rscript

# One-command verification for the versioned M2 baseline. Run from the project
# root: Rscript scripts/m3_validate_release.R. With --remote, verify the
# public commit-pinned endpoint too (after the repository is public).

index_path <- file.path("inst", "extdata", "release-index.json")
if (!file.exists(index_path)) stop("Run this command from the OPCC project root", call. = FALSE)

index <- jsonlite::read_json(index_path, simplifyVector = FALSE)
spec <- index$m2[["2026-06-26"]]
if (is.null(spec)) stop("Baseline 2026-06-26 is absent from the release index", call. = FALSE)

download_and_check <- function(url, expected, suffix) {
  path <- tempfile(fileext = suffix)
  utils::download.file(url, path, mode = "wb", quiet = TRUE)
  actual <- digest::digest(path, algo = "sha256", file = TRUE)
  if (!identical(tolower(actual), tolower(expected))) {
    stop(sprintf("Checksum mismatch for %s", url), call. = FALSE)
  }
  path
}

local_dir <- file.path("releases", "m2", "2026-06-26")
use_remote <- identical(commandArgs(trailingOnly = TRUE), "--remote")
if (!use_remote && dir.exists(local_dir)) {
  manifest_path <- file.path(local_dir, "m2_manifest.json")
  artifact_path <- file.path(local_dir, "opcc_m2_correspondence.csv.gz")
  if (!identical(digest::digest(manifest_path, algo = "sha256", file = TRUE), spec$manifest_sha256)) {
    stop("Local manifest checksum mismatch", call. = FALSE)
  }
  if (!identical(digest::digest(artifact_path, algo = "sha256", file = TRUE), spec$sha256)) {
    stop("Local artifact checksum mismatch", call. = FALSE)
  }
  source_label <- "local versioned artifact"
} else {
  manifest_path <- download_and_check(spec$manifest, spec$manifest_sha256, ".json")
  artifact_path <- download_and_check(spec$artifact, spec$sha256, ".csv.gz")
  on.exit(unlink(c(manifest_path, artifact_path)), add = TRUE)
  source_label <- "remote release endpoint"
}
manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
x <- utils::read.csv(gzfile(artifact_path), stringsAsFactors = FALSE, colClasses = "character")

required <- c("postal_code", "DBUID", "DAUID", "address_weight", "best_link", "confidence")
if (!all(required %in% names(x))) stop("Artifact is missing required columns", call. = FALSE)
if (anyDuplicated(x[c("postal_code", "DBUID")])) stop("Artifact has duplicate postal-code/DB keys", call. = FALSE)
weights <- tapply(as.numeric(x$address_weight), x$postal_code, sum)
best <- tapply(x$best_link == "TRUE", x$postal_code, sum)
if (any(abs(weights - 1) > 1e-8) || any(best != 1L)) stop("Artifact allocation invariants failed", call. = FALSE)
if (!identical(manifest$release_artifact$sha256, spec$sha256)) stop("Manifest/index disagreement", call. = FALSE)

cat(sprintf("Verified OPCC M2 %s (%s): %d rows, %d postal codes.\n", "2026-06-26", source_label, nrow(x), length(unique(x$postal_code))))
