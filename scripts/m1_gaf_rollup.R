library(sf)
library(dplyr)
library(readr)

cat("Starting M1 GAF Rollup...\n\n")
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

# 1. Load the pinned province and DB boundary files
province_path <- file.path(root, ".scratch", "shp", "lpr_000b21a_e.shp")
shp_path <- file.path(root, ".scratch", "shp", "ldb_000b21a_e.shp")
cat(sprintf("Loading province boundary shapefile from %s...\n", province_path))
province_sf <- st_read(province_path, quiet = TRUE)
cat(sprintf("Loading DB shapefile from %s...\n", shp_path))
db_sf <- st_read(shp_path, quiet = TRUE)
cat(sprintf(
  "Ontario DB count: %d\n\n",
  sum(as.character(db_sf$PRUID) == "35", na.rm = TRUE)
))

# 2. Load postal centroids
pc_path <- file.path(root, ".scratch", "postal_centroids", "ontario_postal_centroids.csv")
cat(sprintf("Loading Ontario postal centroids from %s...\n", pc_path))
pc_df <- read_csv(pc_path, show_col_types = FALSE)

# Convert to sf object (WGS84 / EPSG:4326)
cat("Filtering out rows with missing coordinates...\n")
pc_df_clean <- pc_df %>% filter(!is.na(longitude) & !is.na(latitude))
cat(sprintf("Dropped %d rows with missing coordinates.\n", nrow(pc_df) - nrow(pc_df_clean)))

# 3. Exact Ontario validation and DB assignment
cat("Validating Ontario membership and assigning DB status...\n")
pc_db_df <- assign_canonical_ontario_points(
  pc_df_clean,
  province_sf,
  db_sf
)
spatial_report <- attr(pc_db_df, "opcc_spatial_validation")
cat(sprintf(
  paste0(
    "Spatial assignment complete. %d matched; %d explicitly unmatched ",
    "out of %d points.\n\n"
  ),
  spatial_report$matched_points,
  spatial_report$unmatched_points,
  spatial_report$input_points
))

# 4. GAF Rollup
gaf_path <- file.path(root, ".scratch", "gaf", "2021_92-151_X.csv")
cat(sprintf("Loading Geographic Attribute File (GAF) from %s...\n", gaf_path))
# Use read_csv but ensure DBUID is read as character to match the shapefile
gaf_df <- read_csv(gaf_path, col_types = cols(.default = "c"))
required_gaf <- c("DBUID_IDIDU", "DAUID_ADIDU")
if (!all(required_gaf %in% names(gaf_df))) {
  stop("GAF must contain DBUID_IDIDU and DAUID_ADIDU")
}
if (anyDuplicated(gaf_df$DBUID_IDIDU)) {
  stop("GAF contains duplicate DBUID_IDIDU rows")
}
matched <- pc_db_df$db_match_status == "matched_2021_ontario_db"
missing_gaf_db <- setdiff(
  unique(pc_db_df$DBUID[matched]),
  gaf_df$DBUID_IDIDU
)
if (length(missing_gaf_db) > 0L) {
  stop("Some matched Ontario DBs have no GAF mapping")
}

cat("Performing GAF rollup...\n")
final_rollup <- pc_db_df %>% 
  left_join(gaf_df, by = c("DBUID" = "DBUID_IDIDU"))
missing_dauid <- matched & (
  is.na(final_rollup$DAUID_ADIDU) |
    !nzchar(final_rollup$DAUID_ADIDU)
)
if (any(missing_dauid)) {
  stop("Some matched Ontario DBs have no GAF DAUID")
}
validate_canonical_point_geography(final_rollup)

# 5. Save output
out_path <- file.path(root, ".scratch", "postal_centroids", "ontario_postal_gaf_rollup.csv")
cat(sprintf("Saving final rolled-up dataset to %s...\n", out_path))
write_csv(final_rollup, out_path)

cat("\nDone! M1 DB Assignment and GAF Rollup complete.\n")
