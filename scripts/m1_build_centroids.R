# scripts/m1_build_centroids.R
#
# Build Ontario postal code centroid table with full source provenance.
#
# PURPOSE:
#   Produce one row per distinct Ontario postal code containing the best
#   available lat/lon centroid, the source that provided it, and enough
#   lineage to satisfy a legal audit.  Output is intentionally wide so
#   downstream consumers can see every input value and choose their own
#   priority.
#
# SOURCES AND LINEAGE:
#
#   Source A -- Statistics Canada National Address Register (NAR)
#     Catalogue  : 46-26-0002
#     Release    : 2026-06-26
#     Licence    : Open Government Licence - Canada (OGL-Canada)
#                  https://open.canada.ca/en/open-government-licence-canada
#     Download   : https://www150.statcan.gc.ca/n1/pub/46-26-0002/2022001/202606.zip
#     Files used : Addresses/Address_35_part_{1-7}.csv  (postal codes)
#                  Locations/Location_35_part_{1-5}.csv  (WGS84 coords)
#     Join key   : LOC_GUID (present in both Address and Location files)
#     Coord cols : BF_REPPOINT_LATITUDE / BF_REPPOINT_LONGITUDE (preferred)
#                  BG_LATITUDE / BG_LONGITUDE (fallback when REPPOINT missing)
#     Method     : For each postal code, compute the arithmetic mean of all
#                  address-point coordinates that have a populated value.
#                  Priority: BF_REPPOINT > BG (never mix within one record).
#     Postal col : MAIL_POSTAL_CODE (observed postal association -- NOT an
#                  authoritative Canada Post assignment)
#     Coverage   : ~63.5 % of address records have at least one coord pair.
#
#   Source B -- GeoNames Canadian Postal Codes
#     File       : CA_full.csv.zip -> CA_full.txt
#     Licence    : Creative Commons Attribution 4.0 (CC BY 4.0)
#                  https://creativecommons.org/licenses/by/4.0/
#     Download   : https://download.geonames.org/export/zip/CA_full.csv.zip
#     Attribution: "Data from GeoNames (geonames.org), CC BY 4.0"
#     Method     : Direct -- one row per postal code with a single centroid.
#     Ontario    : Filtered by admin_code1 == "ON".
#
# POINT SELECTION PRIORITY (column: point_source):
#   "nar_centroid"  -- code present in NAR with >= 1 address having coords.
#   "geonames"      -- code absent from NAR (or NAR has zero coord coverage);
#                      lat/lon taken directly from GeoNames.
#   "none"          -- NAR-only code with zero coord coverage in NAR and not
#                      in GeoNames.  Latitude/longitude left as NA.
#
#   For codes in BOTH sources the output retains nar_lat/nar_lon AND
#   gn_lat/gn_lon so a consumer can compare or substitute.
#
# OUTPUTS (all in .scratch/postal_centroids/ which is gitignored):
#   ontario_postal_centroids.csv   -- one row per postal code, full provenance
#   centroids_manifest.json        -- run metadata, checksums, row counts
#
# REPRODUCIBILITY:
#   Rerun at any time.  Scratch-cached ZIPs are reused; extraction is skipped
#   if the target file already exists.  Delete .scratch/ to force a clean run.
#
# DEPENDENCIES:
#   install.packages(c("readr", "dplyr", "digest", "jsonlite"))
#
# ASCII-ONLY.  No spatial packages.  Scratch dir is gitignored -- never commit
# downloaded data or derived products without explicit approval.

library(readr)
library(dplyr)
library(digest)
library(jsonlite)

# ---------------------------------------------------------------------------
# 0. Configuration
# ---------------------------------------------------------------------------

NAR_ZIP      <- file.path(getwd(), ".scratch", "m1_nar", "202606.zip")
NAR_SCRATCH  <- file.path(getwd(), ".scratch", "m1_nar")
GN_TXT       <- file.path(getwd(), ".scratch", "m1_geonames", "CA_full.txt")
OUT_DIR      <- file.path(getwd(), ".scratch", "postal_centroids")
OUT_CSV      <- file.path(OUT_DIR, "ontario_postal_centroids.csv")
OUT_MANIFEST <- file.path(OUT_DIR, "centroids_manifest.json")

if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# Normalized ANA NAN format
PC_REGEX <- "^[A-Z][0-9][A-Z] [0-9][A-Z][0-9]$"

normalize_pc <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- gsub("[[:space:]]+", "", x)
  ifelse(nchar(x) == 6L, paste0(substr(x, 1, 3), " ", substr(x, 4, 6)), x)
}

RUN_TS <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
cat("=== m1_build_centroids.R ===\n")
cat("Run:", RUN_TS, "\n\n")

# ---------------------------------------------------------------------------
# 1. Pre-flight checks
# ---------------------------------------------------------------------------

if (!file.exists(NAR_ZIP)) {
  stop("NAR ZIP not found at ", NAR_ZIP,
       "\nRun scripts/m1_nar_profile.R first to download it.")
}
if (!file.exists(GN_TXT)) {
  stop("GeoNames CA_full.txt not found at ", GN_TXT,
       "\nRun scripts/m4_geonames_profile.R first to download and extract it.")
}

cat("[pre] NAR ZIP:      ", NAR_ZIP, "\n")
cat("[pre] GeoNames txt: ", GN_TXT, "\n")

# ---------------------------------------------------------------------------
# 2. Extract NAR Location and Address files (Ontario)
# ---------------------------------------------------------------------------

cat("\n[1] Extracting NAR Location and Address files (Ontario)...\n")

loc_parts <- paste0("Locations/Location_35_part_", 1:5, ".csv")

for (lf in loc_parts) {
  dest <- file.path(NAR_SCRATCH, lf)
  if (file.exists(dest)) {
    cat("    Cached:", basename(dest), "\n")
  } else {
    cat("    Extracting", basename(lf), "...\n")
    if (!dir.exists(file.path(NAR_SCRATCH, "Locations"))) {
      dir.create(file.path(NAR_SCRATCH, "Locations"), recursive = TRUE)
    }
    unzip(NAR_ZIP, files = lf, exdir = NAR_SCRATCH)
  }
}

addr_members <- paste0("Addresses/Address_35_part_", 1:7, ".csv")
for (member in addr_members) {
  dest <- file.path(NAR_SCRATCH, member)
  if (file.exists(dest)) {
    cat("    Cached:", basename(dest), "\n")
  } else {
    cat("    Extracting", basename(member), "...\n")
    dir.create(file.path(NAR_SCRATCH, "Addresses"), recursive = TRUE,
               showWarnings = FALSE)
    unzip(NAR_ZIP, files = member, exdir = NAR_SCRATCH)
  }
}

# ---------------------------------------------------------------------------
# 3. Load NAR Location data (LOC_GUID + WGS84 coords)
# ---------------------------------------------------------------------------

cat("\n[2] Reading NAR Location files (LOC_GUID + coords)...\n")

LOC_COLS <- c("LOC_GUID",
              "BF_REPPOINT_LATITUDE", "BF_REPPOINT_LONGITUDE",
              "BG_LATITUDE",          "BG_LONGITUDE")

read_location_part <- function(path) {
  raw <- readr::read_csv(path,
    col_select  = any_of(LOC_COLS),
    col_types   = cols(.default = col_character()),
    show_col_types = FALSE,
    name_repair = "minimal"
  )
  # Strip BOM from first column name if present
  names(raw) <- gsub("^\xef\xbb\xbf", "", names(raw))
  names(raw) <- gsub("^[[:space:]]+", "", names(raw))
  raw
}

loc_all <- dplyr::bind_rows(lapply(
  file.path(NAR_SCRATCH, loc_parts),
  read_location_part
))

cat("    Location rows loaded:", format(nrow(loc_all), big.mark = ","), "\n")
cat("    Columns:", paste(names(loc_all), collapse = ", "), "\n")

# Coerce to numeric; silently NA on non-numeric strings
loc_all <- loc_all %>%
  mutate(
    bf_lat = suppressWarnings(as.numeric(BF_REPPOINT_LATITUDE)),
    bf_lon = suppressWarnings(as.numeric(BF_REPPOINT_LONGITUDE)),
    bg_lat = suppressWarnings(as.numeric(BG_LATITUDE)),
    bg_lon = suppressWarnings(as.numeric(BG_LONGITUDE)),
    # Best available: BF_REPPOINT preferred; fall back to BG
    best_lat = dplyr::coalesce(bf_lat, bg_lat),
    best_lon = dplyr::coalesce(bf_lon, bg_lon),
    # Track which coord type was used
    coord_type = dplyr::case_when(
      !is.na(bf_lat) ~ "bf_reppoint",
      !is.na(bg_lat) ~ "bg_latlon",
      TRUE           ~ "none"
    )
  ) %>%
  select(LOC_GUID, best_lat, best_lon, coord_type)

n_loc_with_coords <- sum(!is.na(loc_all$best_lat))
cat(sprintf("    Location rows with coords: %s (%.1f%%)\n",
            format(n_loc_with_coords, big.mark = ","),
            100 * n_loc_with_coords / nrow(loc_all)))

# ---------------------------------------------------------------------------
# 4. Load NAR Address data (postal code + LOC_GUID) and join to Location
# ---------------------------------------------------------------------------

cat("\n[3] Reading NAR Address files and joining to Location coords...\n")

addr_parts <- list.files(
  file.path(NAR_SCRATCH, "Addresses"),
  pattern = "^Address_35_",
  full.names = TRUE
)
addr_parts <- sort(addr_parts)
cat("    Address parts found:", length(addr_parts), "\n")

read_address_part <- function(path) {
  raw <- readr::read_csv(path,
    col_select  = any_of(c("LOC_GUID", "MAIL_POSTAL_CODE")),
    col_types   = cols(.default = col_character()),
    show_col_types = FALSE,
    name_repair = "minimal"
  )
  names(raw) <- gsub("^\xef\xbb\xbf", "", names(raw))
  names(raw) <- gsub("^[[:space:]]+", "", names(raw))
  raw %>% mutate(pc_norm = normalize_pc(MAIL_POSTAL_CODE))
}

# Read address parts one at a time to limit peak memory, accumulate aggregates
pc_accum <- NULL

for (ap in addr_parts) {
  cat("    Reading", basename(ap), "...\n")
  addr_chunk <- read_address_part(ap)

  # Join to location coords
  chunk_joined <- addr_chunk %>%
    left_join(loc_all, by = "LOC_GUID")

  # Accumulate: per postal code, running sums for mean computation
  chunk_agg <- chunk_joined %>%
    filter(grepl(PC_REGEX, pc_norm, perl = TRUE)) %>%
    group_by(pc_norm) %>%
    summarise(
      addr_count       = n(),
      addr_with_coords = sum(!is.na(best_lat)),
      sum_lat          = sum(best_lat, na.rm = TRUE),
      sum_lon          = sum(best_lon, na.rm = TRUE),
      .groups = "drop"
    )

  if (is.null(pc_accum)) {
    pc_accum <- chunk_agg
  } else {
    pc_accum <- dplyr::bind_rows(pc_accum, chunk_agg) %>%
      group_by(pc_norm) %>%
      summarise(
        addr_count       = sum(addr_count),
        addr_with_coords = sum(addr_with_coords),
        sum_lat          = sum(sum_lat),
        sum_lon          = sum(sum_lon),
        .groups = "drop"
      )
  }
  rm(addr_chunk, chunk_joined, chunk_agg)
  gc(verbose = FALSE)
}

# Compute final NAR centroids
nar_centroids <- pc_accum %>%
  mutate(
    nar_lat = ifelse(addr_with_coords > 0, sum_lat / addr_with_coords, NA_real_),
    nar_lon = ifelse(addr_with_coords > 0, sum_lon / addr_with_coords, NA_real_)
  ) %>%
  select(pc_norm, nar_lat, nar_lon, addr_count, addr_with_coords)

cat("\n    NAR centroids computed:\n")
cat("    Total NAR postal codes:          ", format(nrow(nar_centroids), big.mark = ","), "\n")
cat("    With at least 1 coord address:   ",
    format(sum(!is.na(nar_centroids$nar_lat)), big.mark = ","), "\n")
cat("    Zero coord coverage:             ",
    format(sum(is.na(nar_centroids$nar_lat)), big.mark = ","), "\n")

# Sanity check: coords should be within Ontario bounding box
on_lat_min <- 41.6; on_lat_max <- 56.9
on_lon_min <- -95.2; on_lon_max <- -74.3

n_outside <- nar_centroids %>%
  filter(!is.na(nar_lat)) %>%
  filter(nar_lat < on_lat_min | nar_lat > on_lat_max |
         nar_lon < on_lon_min | nar_lon > on_lon_max) %>%
  nrow()
if (n_outside > 0) {
  cat("    WARN:", n_outside, "NAR centroids outside Ontario bounding box -- inspect.\n")
} else {
  cat("    Bounding-box check: all NAR centroids within Ontario extent.\n")
}

# ---------------------------------------------------------------------------
# 5. Load GeoNames Ontario
# ---------------------------------------------------------------------------

cat("\n[4] Loading GeoNames Ontario...\n")

GEONAMES_COLS <- c(
  "country_code", "postal_code", "place_name",
  "admin_name1",  "admin_code1",
  "admin_name2",  "admin_code2",
  "admin_name3",  "admin_code3",
  "latitude",     "longitude",   "accuracy"
)

gn_raw <- readr::read_tsv(GN_TXT,
  col_names      = GEONAMES_COLS,
  col_types      = cols(.default = col_character()),
  show_col_types = FALSE
)

gn_on <- gn_raw %>%
  filter(admin_code1 == "ON") %>%
  mutate(
    pc_norm = normalize_pc(postal_code),
    gn_lat  = suppressWarnings(as.numeric(latitude)),
    gn_lon  = suppressWarnings(as.numeric(longitude)),
    gn_accuracy = suppressWarnings(as.numeric(accuracy))
  ) %>%
  filter(grepl(PC_REGEX, pc_norm, perl = TRUE), !is.na(gn_lat)) %>%
  group_by(pc_norm) %>%
  slice(1) %>%           # GeoNames has one row per code; keep first if duplicated
  ungroup() %>%
  select(pc_norm, gn_lat, gn_lon, gn_accuracy, gn_place_name = place_name)

cat("    GeoNames Ontario codes:", format(nrow(gn_on), big.mark = ","), "\n")

# ---------------------------------------------------------------------------
# 6. Build final combined table
# ---------------------------------------------------------------------------

cat("\n[5] Building combined centroid table...\n")

all_codes <- dplyr::full_join(nar_centroids, gn_on, by = "pc_norm")

combined <- all_codes %>%
  mutate(
    in_nar      = !is.na(addr_count),
    in_geonames = !is.na(gn_lat),

    # Select best point
    point_source = dplyr::case_when(
      in_nar & !is.na(nar_lat)  ~ "nar_centroid",
      in_geonames                ~ "geonames",
      TRUE                       ~ "none"
    ),
    point_method = dplyr::case_when(
      point_source == "nar_centroid" ~ "nar_address_mean_wgs84",
      point_source == "geonames"     ~ "geonames_direct_wgs84",
      TRUE                           ~ "none"
    ),
    latitude  = dplyr::case_when(
      point_source == "nar_centroid" ~ nar_lat,
      point_source == "geonames"     ~ gn_lat,
      TRUE                           ~ NA_real_
    ),
    longitude = dplyr::case_when(
      point_source == "nar_centroid" ~ nar_lon,
      point_source == "geonames"     ~ gn_lon,
      TRUE                           ~ NA_real_
    ),

    # NAR release and GeoNames retrieval dates for provenance
    nar_release_date     = if_else(in_nar, "2026-06-26", NA_character_),
    nar_catalogue        = if_else(in_nar, "46-26-0002", NA_character_),
    nar_licence          = if_else(in_nar, "OGL-Canada", NA_character_),
    nar_postal_note      = if_else(in_nar,
      "observed postal association -- not authoritative Canada Post assignment",
      NA_character_),
    gn_retrieval_date    = if_else(in_geonames, "2026-07-17", NA_character_),
    gn_licence           = if_else(in_geonames, "CC BY 4.0", NA_character_),
    gn_attribution       = if_else(in_geonames,
      "Data from GeoNames (geonames.org), CC BY 4.0", NA_character_)
  ) %>%
  select(
    postal_code          = pc_norm,
    latitude,
    longitude,
    point_source,
    point_method,
    in_nar,
    in_geonames,
    nar_lat,
    nar_lon,
    nar_address_count    = addr_count,
    nar_addr_with_coords = addr_with_coords,
    nar_release_date,
    nar_catalogue,
    nar_licence,
    nar_postal_note,
    gn_lat,
    gn_lon,
    gn_accuracy,
    gn_place_name,
    gn_retrieval_date,
    gn_licence,
    gn_attribution
  ) %>%
  arrange(postal_code)

# ---------------------------------------------------------------------------
# 7. Summary report
# ---------------------------------------------------------------------------

cat("\n[6] Summary\n")
cat(strrep("-", 60), "\n")
cat(sprintf("  Total distinct postal codes : %s\n",
            format(nrow(combined), big.mark = ",")))
cat(sprintf("  In NAR                      : %s\n",
            format(sum(combined$in_nar), big.mark = ",")))
cat(sprintf("  In GeoNames                 : %s\n",
            format(sum(combined$in_geonames), big.mark = ",")))
cat(sprintf("  In both                     : %s\n",
            format(sum(combined$in_nar & combined$in_geonames), big.mark = ",")))
cat(sprintf("  NAR only                    : %s\n",
            format(sum(combined$in_nar & !combined$in_geonames), big.mark = ",")))
cat(sprintf("  GeoNames only               : %s\n",
            format(sum(!combined$in_nar & combined$in_geonames), big.mark = ",")))
cat(strrep("-", 60), "\n")
cat(sprintf("  point_source = nar_centroid : %s\n",
            format(sum(combined$point_source == "nar_centroid"), big.mark = ",")))
cat(sprintf("  point_source = geonames     : %s\n",
            format(sum(combined$point_source == "geonames"), big.mark = ",")))
cat(sprintf("  point_source = none         : %s\n",
            format(sum(combined$point_source == "none"), big.mark = ",")))
cat(sprintf("  Codes with a lat/lon point  : %s\n",
            format(sum(!is.na(combined$latitude)), big.mark = ",")))
cat(strrep("-", 60), "\n")

# ---------------------------------------------------------------------------
# 8. Write output CSV
# ---------------------------------------------------------------------------

cat("\n[7] Writing", OUT_CSV, "...\n")
readr::write_csv(combined, OUT_CSV)
cat("    Rows written:", format(nrow(combined), big.mark = ","), "\n")

out_sha256   <- digest::digest(OUT_CSV, algo = "sha256", file = TRUE)
out_size     <- file.info(OUT_CSV)$size
nar_sha256   <- digest::digest(NAR_ZIP, algo = "sha256", file = TRUE)
gn_sha256    <- digest::digest(
  file.path(getwd(), ".scratch", "m1_geonames", "CA_full.csv.zip"),
  algo = "sha256", file = TRUE
)
cat("    SHA-256:", out_sha256, "\n")

# ---------------------------------------------------------------------------
# 9. Write manifest
# ---------------------------------------------------------------------------

cat("\n[8] Writing manifest...\n")

manifest <- list(
  manifest_version = 1L,
  run_timestamp    = RUN_TS,
  output = list(
    path         = OUT_CSV,
    sha256       = out_sha256,
    size_bytes   = out_size,
    total_rows   = nrow(combined),
    cols         = names(combined)
  ),
  counts = list(
    total_codes        = nrow(combined),
    in_nar             = sum(combined$in_nar),
    in_geonames        = sum(combined$in_geonames),
    in_both            = sum(combined$in_nar & combined$in_geonames),
    nar_only           = sum(combined$in_nar & !combined$in_geonames),
    geonames_only      = sum(!combined$in_nar & combined$in_geonames),
    point_nar_centroid = sum(combined$point_source == "nar_centroid"),
    point_geonames     = sum(combined$point_source == "geonames"),
    point_none         = sum(combined$point_source == "none"),
    codes_with_point   = sum(!is.na(combined$latitude))
  ),
  sources = list(
    nar = list(
      catalogue        = "46-26-0002",
      name             = "National Address Register",
      publisher        = "Statistics Canada",
      release_date     = "2026-06-26",
      licence          = "Open Government Licence - Canada",
      licence_url      = "https://open.canada.ca/en/open-government-licence-canada",
      download_url     = "https://www150.statcan.gc.ca/n1/pub/46-26-0002/2022001/202606.zip",
      zip_sha256       = nar_sha256,
      address_files    = paste0("Addresses/Address_35_part_", 1:7, ".csv"),
      location_files   = paste0("Locations/Location_35_part_", 1:5, ".csv"),
      coord_system     = "WGS84 (EPSG:4326) via BF_REPPOINT_LATITUDE/LONGITUDE",
      coord_fallback   = "BG_LATITUDE/BG_LONGITUDE (also WGS84, from Location files)",
      postal_note      = "Postal codes described as observed postal associations only"
    ),
    geonames = list(
      name             = "GeoNames Canadian Postal Codes",
      publisher        = "GeoNames (geonames.org)",
      licence          = "Creative Commons Attribution 4.0",
      licence_url      = "https://creativecommons.org/licenses/by/4.0/",
      attribution      = "Data from GeoNames (geonames.org), CC BY 4.0",
      download_url     = "https://download.geonames.org/export/zip/CA_full.csv.zip",
      zip_sha256       = gn_sha256,
      retrieval_date   = "2026-07-17",
      coord_system     = "WGS84 (EPSG:4326), direct per-code centroid",
      ontario_filter   = "admin_code1 == 'ON'"
    )
  ),
  point_selection_policy = list(
    priority_1 = "nar_centroid: code in NAR with >= 1 address having WGS84 coords",
    priority_2 = "geonames: code absent from NAR, or NAR has no coord coverage",
    priority_3 = "none: NAR-only code with zero coord coverage and not in GeoNames"
  ),
  notes = paste(
    "NAR Address and Location files are joined on LOC_GUID.",
    "NAR centroid = arithmetic mean of all address BF_REPPOINT (preferred) or BG coords.",
    "GeoNames provides one direct centroid per code; taken as-is.",
    "This product contains no Canada Post licensed data.",
    "Postal code fields from NAR are described only as observed postal associations.",
    sep = " "
  )
)

jsonlite::write_json(manifest, path = OUT_MANIFEST, pretty = TRUE, auto_unbox = TRUE)
cat("    Manifest written:", OUT_MANIFEST, "\n")

cat("\n=== Done ===\n")
cat("Output:", OUT_CSV, "\n")
