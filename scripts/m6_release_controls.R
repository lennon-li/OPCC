#!/usr/bin/env Rscript

# M6 release controls. These pure helpers audit immutable release-index entries
# and compare successive artifacts without changing a published release.

sha256_file <- function(path) digest::digest(path, algo = "sha256", file = TRUE)

is_commit_pinned_raw_url <- function(url) {
  grepl("^https://raw[.]githubusercontent[.]com/[^/]+/[^/]+/[0-9a-f]{40}/", url)
}

audit_release_index <- function(index_path, releases_root = "releases") {
  index <- jsonlite::read_json(index_path, simplifyVector = FALSE)
  kinds <- intersect(c("m2", "m5"), names(index))
  rows <- lapply(kinds, function(kind) {
    lapply(names(index[[kind]]), function(vintage) {
      spec <- index[[kind]][[vintage]]
      artifact_name <- basename(spec$artifact)
      manifest_name <- basename(spec$manifest)
      release_dir <- file.path(releases_root, kind, vintage)
      artifact_path <- file.path(release_dir, artifact_name)
      manifest_path <- file.path(release_dir, manifest_name)
      if (!is_commit_pinned_raw_url(spec$artifact) || !is_commit_pinned_raw_url(spec$manifest)) {
        stop(sprintf("%s %s has a non-immutable release URL", kind, vintage), call. = FALSE)
      }
      if (!file.exists(artifact_path) || !file.exists(manifest_path)) {
        stop(sprintf("%s %s is missing its versioned artifact or manifest", kind, vintage), call. = FALSE)
      }
      if (!identical(sha256_file(artifact_path), spec$sha256) ||
          !identical(sha256_file(manifest_path), spec$manifest_sha256)) {
        stop(sprintf("%s %s checksum drifted from the release index", kind, vintage), call. = FALSE)
      }
      data.frame(kind = kind, vintage = vintage, artifact = artifact_name,
                 manifest = manifest_name, stringsAsFactors = FALSE)
    })
  })
  do.call(rbind, unlist(rows, recursive = FALSE))
}

release_drift_report <- function(previous, candidate, key_columns, weight_column = "allocation_weight") {
  required <- c(key_columns, weight_column)
  if (!all(required %in% names(previous)) || !all(required %in% names(candidate))) {
    stop("Both inputs must contain the key and allocation-weight columns", call. = FALSE)
  }
  key <- function(x) do.call(paste, c(x[key_columns], sep = "\r"))
  old_key <- key(previous)
  new_key <- key(candidate)
  shared <- intersect(old_key, new_key)
  old_weight <- setNames(as.numeric(previous[[weight_column]]), old_key)
  new_weight <- setNames(as.numeric(candidate[[weight_column]]), new_key)
  list(
    prior_rows = nrow(previous),
    candidate_rows = nrow(candidate),
    added_keys = length(setdiff(new_key, old_key)),
    removed_keys = length(setdiff(old_key, new_key)),
    changed_weight_keys = sum(abs(new_weight[shared] - old_weight[shared]) > 1e-12),
    prior_postal_codes = length(unique(previous$postal_code)),
    candidate_postal_codes = length(unique(candidate$postal_code))
  )
}

run_release_audit <- function() {
  root <- getwd()
  index_path <- file.path(root, "inst", "extdata", "release-index.json")
  if (!file.exists(index_path)) stop("Run this command from the OPCC project root", call. = FALSE)
  report <- audit_release_index(index_path, file.path(root, "releases"))
  cat(jsonlite::toJSON(report, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), "\n")
}

if (sys.nframe() == 0) run_release_audit()
