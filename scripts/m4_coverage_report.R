#!/usr/bin/env Rscript

# Reproduce the M4 GeoNames coverage and overlap report from versioned OPCC
# artifacts. This script does not construct a release or assign uncertainty.

root <- getwd()
baseline_path <- file.path(root, "releases", "m2", "2026-06-26", "opcc_m2_correspondence.csv.gz")
candidate_path <- file.path(root, "releases", "m2", "2026-07-19-geonames-amendment", "opcc_m2_correspondence.csv.gz")
points_path <- file.path(root, "releases", "m1", "2026-07-19-geonames-points", "opcc_m1_geonames_points.csv.gz")

for (path in c(baseline_path, candidate_path, points_path)) {
  if (!file.exists(path)) stop("Missing versioned artifact: ", path, call. = FALSE)
}

read_gzip_csv <- function(path) read.csv(gzfile(path), stringsAsFactors = FALSE, check.names = FALSE)
has_value <- function(x) !is.na(x) & nzchar(x)

baseline <- read_gzip_csv(baseline_path)
candidate <- read_gzip_csv(candidate_path)
points <- read_gzip_csv(points_path)

required_candidate <- c("postal_code", "evidence_class")
required_points <- c("postal_code", "DBUID", "DAUID_ADIDU")
if (!all(required_candidate %in% names(candidate))) stop("Candidate schema is incomplete", call. = FALSE)
if (!all(required_points %in% names(points))) stop("Point schema is incomplete", call. = FALSE)

baseline_pc <- unique(baseline$postal_code)
candidate_pc <- unique(candidate$postal_code)
geonames_pc <- unique(candidate$postal_code[candidate$evidence_class == "geonames_supplementary"])
point_pc <- unique(points$postal_code)
resolved_point <- has_value(points$DBUID) & has_value(points$DAUID_ADIDU)

report <- list(
  report = "M4 GeoNames coverage and disagreement report",
  baseline_vintage = "2026-06-26",
  candidate_vintage = "2026-07-19-geonames-amendment",
  baseline_postal_codes = length(baseline_pc),
  candidate_postal_codes = length(candidate_pc),
  candidate_added_postal_codes = length(setdiff(candidate_pc, baseline_pc)),
  candidate_geonames_rows = sum(candidate$evidence_class == "geonames_supplementary"),
  candidate_geonames_postal_codes = length(geonames_pc),
  source_geonames_points = length(point_pc),
  source_geonames_resolved_points = sum(resolved_point),
  source_geonames_unmatched_points = sum(!resolved_point),
  geonames_postal_codes_overlapping_baseline = length(intersect(geonames_pc, baseline_pc)),
  source_point_postal_codes_overlapping_baseline = length(intersect(point_pc, baseline_pc)),
  disagreement_status = "not_estimable_no_shared_postal_codes",
  calibration_status = "not_run_no_paired_nar_geonames_evidence",
  interpretation = paste(
    "GeoNames is retained as a source-separated supplementary point layer.",
    "No calibrated cross-source disagreement or uncertainty weights are published from these artifacts."
  )
)

expected <- c(
  baseline_postal_codes = 282409L,
  candidate_postal_codes = 299743L,
  candidate_added_postal_codes = 17334L,
  candidate_geonames_rows = 17334L,
  source_geonames_points = 17373L,
  source_geonames_resolved_points = 17334L,
  source_geonames_unmatched_points = 39L,
  geonames_postal_codes_overlapping_baseline = 0L,
  source_point_postal_codes_overlapping_baseline = 0L
)
observed <- vapply(names(expected), function(name) as.integer(report[[name]]), integer(1))
names(observed) <- names(expected)
if (!identical(observed, expected)) {
  stop("Versioned M4 coverage report drifted; inspect the source artifacts before updating expectations", call. = FALSE)
}

jsonlite::write_json(report, stdout(), auto_unbox = TRUE, pretty = TRUE)
