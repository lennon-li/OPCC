library(sf)
library(dplyr)
library(readr)

cat("Starting M1 GAF Rollup...\n\n")
root <- getwd()

# 1. Load and filter the DB shapefile
shp_path <- file.path(root, ".scratch", "shp", "ldb_000b21a_e.shp")
cat(sprintf("Loading DB shapefile from %s...\n", shp_path))
db_sf <- st_read(shp_path, quiet = TRUE)

cat("Filtering DB shapefile to Ontario (PRUID == 35)...\n")
db_on <- db_sf %>% filter(PRUID == "35")
cat(sprintf("Ontario DB count: %d\n\n", nrow(db_on)))

# 2. Load postal centroids
pc_path <- file.path(root, ".scratch", "postal_centroids", "ontario_postal_centroids.csv")
cat(sprintf("Loading Ontario postal centroids from %s...\n", pc_path))
pc_df <- read_csv(pc_path, show_col_types = FALSE)

# Convert to sf object (WGS84 / EPSG:4326)
cat("Filtering out rows with missing coordinates...\n")
pc_df_clean <- pc_df %>% filter(!is.na(longitude) & !is.na(latitude))
cat(sprintf("Dropped %d rows with missing coordinates.\n", nrow(pc_df) - nrow(pc_df_clean)))

cat("Converting postal centroids to spatial points...\n")
pc_sf <- st_as_sf(pc_df_clean, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

# Transform points to match the DB shapefile's CRS
db_crs <- st_crs(db_on)
cat("Transforming points to match DB CRS...\n")
pc_sf_proj <- st_transform(pc_sf, db_crs)

# 3. Spatial Join (Point in Polygon)
cat("Performing spatial join (assigning DB to each postal code)...\n")
# We only need the DBUID from the polygon
db_subset <- db_on %>% select(DBUID)
pc_db_join <- st_join(pc_sf_proj, db_subset, join = st_intersects)

# Drop geometry to make it a standard dataframe
pc_db_df <- st_drop_geometry(pc_db_join)
cat(sprintf("Spatial join complete. %d postal codes matched to a DB out of %d.\n\n", 
            sum(!is.na(pc_db_df$DBUID)), nrow(pc_db_df)))

# 4. GAF Rollup
gaf_path <- file.path(root, ".scratch", "gaf", "2021_92-151_X.csv")
cat(sprintf("Loading Geographic Attribute File (GAF) from %s...\n", gaf_path))
# Use read_csv but ensure DBUID is read as character to match the shapefile
gaf_df <- read_csv(gaf_path, col_types = cols(.default = "c"))

cat("Performing GAF rollup...\n")
final_rollup <- pc_db_df %>% 
  left_join(gaf_df, by = c("DBUID" = "DBUID_IDIDU"))

# 5. Save output
out_path <- file.path(root, ".scratch", "postal_centroids", "ontario_postal_gaf_rollup.csv")
cat(sprintf("Saving final rolled-up dataset to %s...\n", out_path))
write_csv(final_rollup, out_path)

cat("\nDone! M1 DB Assignment and GAF Rollup complete.\n")
