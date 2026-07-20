#!/usr/bin/env Rscript

# One-command verification for the versioned M5 direct DA artifact. Run from
# the project root: Rscript scripts/m5_validate_release.R.

index_path <- file.path("inst", "extdata", "release-index.json")
if (!file.exists(index_path)) stop("Run this command from the OPCC project root", call. = FALSE)

index <- jsonlite::read_json(index_path, simplifyVector = FALSE)
spec <- index$m5[["2026-06-26"]]
if (is.null(spec)) stop("M5 vintage 2026-06-26 is absent from the release index", call. = FALSE)

release_dir <- file.path("releases", "m5", "2026-06-26")
artifact_path <- file.path(release_dir, "opcc_m5_da_correspondence.csv.gz")
manifest_path <- file.path(release_dir, "m5_manifest.json")
if (!file.exists(artifact_path) || !file.exists(manifest_path)) {
  stop("Missing versioned M5 artifact or manifest", call. = FALSE)
}
if (!identical(digest::digest(artifact_path, algo = "sha256", file = TRUE), spec$sha256)) {
  stop("M5 artifact checksum mismatch", call. = FALSE)
}
if (!identical(digest::digest(manifest_path, algo = "sha256", file = TRUE), spec$manifest_sha256)) {
  stop("M5 manifest checksum mismatch", call. = FALSE)
}

manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
x <- utils::read.csv(gzfile(artifact_path), stringsAsFactors = FALSE, colClasses = "character")
required <- c(
  "postal_code", "DAUID", "allocation_weight", "best_link",
  "n_contributing_dbs", "contributing_dbuids", "source_vintages"
)
if (!all(required %in% names(x))) stop("M5 artifact schema is incomplete", call. = FALSE)
if (anyDuplicated(x[c("postal_code", "DAUID")])) stop("Duplicate postal-code/DA links", call. = FALSE)
if (any(!nzchar(x$DAUID) | !nzchar(x$contributing_dbuids) | !nzchar(x$source_vintages))) {
  stop("M5 artifact has missing identifier or lineage values", call. = FALSE)
}
weights <- tapply(as.numeric(x$allocation_weight), x$postal_code, sum)
best <- tapply(x$best_link == "TRUE", x$postal_code, sum)
if (any(!is.finite(weights)) || any(abs(weights - 1) > 1e-8) || any(best != 1L)) {
  stop("M5 allocation invariants failed", call. = FALSE)
}
if (!identical(manifest$release_artifact$sha256, spec$sha256)) {
  stop("M5 manifest/index disagreement", call. = FALSE)
}

cat(sprintf("Verified OPCC M5 2026-06-26: %d DA rows, %d postal codes.\n", nrow(x), length(unique(x$postal_code))))
