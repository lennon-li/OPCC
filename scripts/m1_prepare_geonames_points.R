#!/usr/bin/env Rscript

# Build the public, source-qualified M1 supplementary-point artifact from the
# reproducible M1 GAF rollup. Points inside Ontario without a 2021 DB match
# remain visible with an explicit unmatched status.

root <- getwd()
helper_path <- file.path(
  root,
  "scripts",
  "lib",
  "canonical_point_assignment.R"
)
if (!file.exists(helper_path)) {
  stop("Missing canonical point-assignment helper: ", helper_path)
}
source(helper_path)
input <- file.path(root, ".scratch", "postal_centroids", "ontario_postal_gaf_rollup.csv")
output_dir <- file.path(root, "releases", "m1", "2026-07-19-geonames-points")
output <- file.path(output_dir, "opcc_m1_geonames_points.csv.gz")

if (!file.exists(input)) stop("Missing M1 rollup: ", input, call. = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

required <- c(
  "postal_code", "latitude", "longitude", "point_source", "point_method",
  "DBUID", "DAUID_ADIDU", "db_match_status", "gn_accuracy", "gn_place_name",
  "gn_retrieval_date", "gn_licence", "gn_attribution"
)
points <- read.csv(input, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE)
if (!all(required %in% names(points))) stop("M1 rollup is missing required fields", call. = FALSE)
points <- points[points$point_source == "geonames", required, drop = FALSE]
points$latitude <- as.numeric(points$latitude)
points$longitude <- as.numeric(points$longitude)
points$gn_accuracy <- as.numeric(points$gn_accuracy)
points <- points[order(points$postal_code), , drop = FALSE]
point_report <- validate_canonical_point_geography(points)

con <- gzfile(output, "wt")
write.csv(points, con, row.names = FALSE, na = "")
close(con)

message(sprintf("Wrote %d GeoNames supplementary points to %s", nrow(points), output))
message(sprintf("Rows with DB/DA: %d; without DB/DA: %d",
  point_report$matched_points,
  point_report$unmatched_points
)
)
