# scripts/m1_release.R
#
# Publish the M1 NAR + GeoNames centroid scratch output as a versioned,
# redistributable release artifact with a manifest.
#
# The script takes no arguments by default; it reads the scratch manifest
# produced by scripts/m1_build_centroids.R and writes:
#   releases/m1/<vintage>/opcc_m1_centroids.csv.gz
#   releases/m1/<vintage>/m1_manifest.json
#
# ASCII-ONLY. No restricted data is touched.

library(readr)
library(digest)
library(jsonlite)

SCRATCH_DIR <- file.path(getwd(), ".scratch", "postal_centroids")
SCRATCH_CSV <- file.path(SCRATCH_DIR, "ontario_postal_centroids.csv")
SCRATCH_MAN <- file.path(SCRATCH_DIR, "centroids_manifest.json")

if (!file.exists(SCRATCH_CSV)) {
  stop("Scratch centroid CSV not found at ", SCRATCH_CSV,
       "\nRun scripts/m1_build_centroids.R first.")
}
if (!file.exists(SCRATCH_MAN)) {
  stop("Scratch manifest not found at ", SCRATCH_MAN)
}

scratch_manifest <- jsonlite::read_json(SCRATCH_MAN)

vintage <- scratch_manifest$sources$nar$release_date
RELEASE_DIR <- file.path(getwd(), "releases", "m1",
                         paste0(vintage, "-nar-geonames-centroids"))
RELEASE_CSV_GZ <- file.path(RELEASE_DIR, "opcc_m1_centroids.csv.gz")
RELEASE_MAN <- file.path(RELEASE_DIR, "m1_manifest.json")

if (!dir.exists(RELEASE_DIR)) dir.create(RELEASE_DIR, recursive = TRUE)

cat("=== m1_release.R ===\n")
cat("Vintage:", vintage, "\n")

# Read and gzip the CSV.
combined <- readr::read_csv(SCRATCH_CSV, show_col_types = FALSE)
cat("Rows read:", format(nrow(combined), big.mark = ","), "\n")

con <- gzfile(RELEASE_CSV_GZ, "wb")
write.csv(combined, con, row.names = FALSE, na = "")
close(con)

gz_size <- file.info(RELEASE_CSV_GZ)$size
gz_sha256 <- digest::digest(RELEASE_CSV_GZ, algo = "sha256", file = TRUE)
csv_sha256 <- scratch_manifest$output$sha256
csv_size <- scratch_manifest$output$size_bytes

cat("Release artifact:", RELEASE_CSV_GZ, "\n")
cat("  GZ  SHA-256:", gz_sha256, "\n")
cat("  GZ  size:   ", format(gz_size, big.mark = ","), "bytes\n")

release_manifest <- list(
  manifest_version = 2L,
  release_type = "m1_centroids",
  release_date = vintage,
  run_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  generator = list(
    script = "scripts/m1_build_centroids.R",
    release_script = "scripts/m1_release.R",
    repo_sha = system("git rev-parse HEAD", intern = TRUE)
  ),
  artifact = list(
    file = basename(RELEASE_CSV_GZ),
    format = "gzip-compressed CSV",
    schema = "postal_code, latitude, longitude, point_source, point_method, ...",
    total_rows = nrow(combined),
    csv_sha256 = csv_sha256,
    csv_size_bytes = csv_size,
    gz_sha256 = gz_sha256,
    gz_size_bytes = gz_size
  ),
  sources = scratch_manifest$sources,
  counts = scratch_manifest$counts,
  point_selection_policy = scratch_manifest$point_selection_policy,
  redistribution = list(
    assessment = "Permitted under NAR Open Government Licence - Canada and GeoNames CC BY 4.0, with attribution.",
    nar_attribution = "Statistics Canada, National Address Register (46-26-0002, 2026-06-26), Open Government Licence - Canada.",
    geonames_attribution = "Data from GeoNames (geonames.org), CC BY 4.0."
  ),
  notes = paste(
    "This M1 release is the full NAR + GeoNames Ontario postal centroid table.",
    "It replaces the earlier GeoNames-only supplementary point artifact.",
    "Postal codes are described only as observed postal associations.",
    "This product contains no Canada Post licensed data.",
    sep = " "
  )
)

jsonlite::write_json(release_manifest, path = RELEASE_MAN, pretty = TRUE,
                    auto_unbox = TRUE)
cat("Manifest written:", RELEASE_MAN, "\n")
cat("=== Done ===\n")
