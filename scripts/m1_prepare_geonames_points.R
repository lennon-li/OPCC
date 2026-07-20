#!/usr/bin/env Rscript

# Build the public, source-qualified M1 supplementary-point artifact from the
# reproducible M1 GAF rollup. This intentionally retains the 39 GeoNames rows
# outside a 2021 Ontario DB so non-assignment is visible rather than discarded.

root <- getwd()
input <- file.path(root, ".scratch", "postal_centroids", "ontario_postal_gaf_rollup.csv")
output_dir <- file.path(root, "releases", "m1", "2026-07-19-geonames-points")
output <- file.path(output_dir, "opcc_m1_geonames_points.csv.gz")

if (!file.exists(input)) stop("Missing M1 rollup: ", input, call. = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

required <- c(
  "postal_code", "latitude", "longitude", "point_source", "point_method",
  "DBUID", "DAUID_ADIDU", "gn_accuracy", "gn_place_name",
  "gn_retrieval_date", "gn_licence", "gn_attribution"
)
points <- read.csv(input, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE)
if (!all(required %in% names(points))) stop("M1 rollup is missing required fields", call. = FALSE)
points <- points[points$point_source == "geonames", required, drop = FALSE]
points$latitude <- as.numeric(points$latitude)
points$longitude <- as.numeric(points$longitude)
points$gn_accuracy <- as.numeric(points$gn_accuracy)
points <- points[order(points$postal_code), , drop = FALSE]

con <- gzfile(output, "wt")
write.csv(points, con, row.names = FALSE, na = "")
close(con)

message(sprintf("Wrote %d GeoNames supplementary points to %s", nrow(points), output))
message(sprintf("Rows with DB/DA: %d; without DB/DA: %d",
  sum(!is.na(points$DBUID) & nzchar(points$DBUID) & !is.na(points$DAUID_ADIDU) & nzchar(points$DAUID_ADIDU)),
  sum(is.na(points$DBUID) | !nzchar(points$DBUID) | is.na(points$DAUID_ADIDU) | !nzchar(points$DAUID_ADIDU))
)
)
