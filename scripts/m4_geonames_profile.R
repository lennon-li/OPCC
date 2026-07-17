# scripts/m4_geonames_profile.R
#
# Profile GeoNames Canadian Postal Codes, Ontario subset
# Licence: CC BY 4.0 -- https://creativecommons.org/licenses/by/4.0/
# Role: accept-supplementary (reference centroid layer only)
#
# ASCII-only. No spatial packages. Tab-delimited, no header row.
# Scratch dir is gitignored -- never commit downloaded data.
# Attribution required: "Data from GeoNames (geonames.org), CC BY 4.0"

library(readr)
library(dplyr)
library(digest)

GEONAMES_URL <- "https://download.geonames.org/export/zip/CA_full.csv.zip"
ONTARIO_FSA  <- "^[KLMNP]"
PC_REGEX     <- "^[A-Z][0-9][A-Z] [0-9][A-Z][0-9]$"

# Standard GeoNames postal-code file schema (no header -- assigned by position)
GEONAMES_COLS <- c(
  "country_code", "postal_code", "place_name",
  "admin_name1", "admin_code1",
  "admin_name2", "admin_code2",
  "admin_name3", "admin_code3",
  "latitude", "longitude", "accuracy"
)

SCRATCH_DIR <- file.path(getwd(), ".scratch", "m1_geonames")
if (!dir.exists(SCRATCH_DIR)) dir.create(SCRATCH_DIR, recursive = TRUE)

gn_zip   <- file.path(SCRATCH_DIR, "CA_full.csv.zip")
manifest <- file.path(SCRATCH_DIR, "m1_geonames_manifest.json")

cat("=== GeoNames Canadian Postal Codes Profile ===\n")
cat("URL:", GEONAMES_URL, "\n\n")

# ---------------------------------------------------------------------------
# 1. Download
# ---------------------------------------------------------------------------
if (file.exists(gn_zip) && file.info(gn_zip)$size > 1e5) {
  cat("[1] Cached zip found, skipping download.\n")
} else {
  cat("[1] Downloading GeoNames CA_full.csv.zip...\n")
  exit_code <- system2("curl", args = c("-L", "-o", shQuote(gn_zip), shQuote(GEONAMES_URL)),
                       stdout = "", stderr = "")
  if (exit_code != 0) stop("curl download failed with exit code ", exit_code)
}

file_size <- file.info(gn_zip)$size
sha256    <- digest::digest(gn_zip, algo = "sha256", file = TRUE)
cat("    Size:", format(file_size / 1e6, digits = 4), "MB\n")
cat("    SHA-256:", sha256, "\n")

# ---------------------------------------------------------------------------
# 2. Read (tab-delimited, no header)
# ---------------------------------------------------------------------------
cat("\n[2] ZIP contents:\n")
zip_list <- unzip(gn_zip, list = TRUE)
print(zip_list[, c("Name", "Length")], row.names = FALSE)

csv_name <- zip_list$Name[grepl("CA_full\\.csv$|CA\\.txt$|\\.csv$|\\.txt$",
                                zip_list$Name, ignore.case = TRUE)][1]
csv_path <- file.path(SCRATCH_DIR, csv_name)
if (!file.exists(csv_path)) unzip(gn_zip, files = csv_name, exdir = SCRATCH_DIR)

gn_raw <- readr::read_tsv(csv_path, col_names = FALSE, show_col_types = FALSE)

if (ncol(gn_raw) == length(GEONAMES_COLS)) {
  names(gn_raw) <- GEONAMES_COLS
} else {
  cat("    WARN: expected", length(GEONAMES_COLS),
      "columns but found", ncol(gn_raw), "-- review GEONAMES_COLS.\n")
  cat("    Proceeding with generic column names.\n")
}

cat("    Columns:", paste(names(gn_raw), collapse = ", "), "\n")
cat("    Total rows:", format(nrow(gn_raw), big.mark = ","), "\n")

# ---------------------------------------------------------------------------
# 3. Ontario filter (FSA prefix + admin_code1 cross-check)
# ---------------------------------------------------------------------------
cat("\n[3] Ontario filter...\n")
normalize_pc <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("[[:space:]]+", "", x)
  ifelse(nchar(x) == 6, paste0(substr(x, 1, 3), " ", substr(x, 4, 6)), x)
}

pc_col  <- if ("postal_code" %in% names(gn_raw)) "postal_code" else names(gn_raw)[2]
pc_norm <- normalize_pc(gn_raw[[pc_col]])
on_mask <- grepl(ONTARIO_FSA, pc_norm, perl = TRUE)
gn_on   <- gn_raw[on_mask, ]
cat("    Ontario rows (FSA prefix):", format(nrow(gn_on), big.mark = ","), "\n")

if ("admin_code1" %in% names(gn_raw)) {
  on_by_prov <- sum(gn_raw[["admin_code1"]] == "ON", na.rm = TRUE)
  cat("    Ontario rows by admin_code1 == ON:",
      format(on_by_prov, big.mark = ","), "\n")
  if (abs(nrow(gn_on) - on_by_prov) > 100) {
    cat("    WARN: FSA filter and admin_code1 filter disagree by > 100 rows -- inspect.\n")
  }
}

# ---------------------------------------------------------------------------
# 4. Postal-code profile
# ---------------------------------------------------------------------------
cat("\n[4] Postal-code profile...\n")
pc_norm_on <- normalize_pc(gn_on[[pc_col]])
n_valid    <- sum(grepl(PC_REGEX, pc_norm_on, perl = TRUE), na.rm = TRUE)
n_uniq     <- length(unique(pc_norm_on[grepl(PC_REGEX, pc_norm_on, perl = TRUE)]))
n_miss     <- sum(is.na(gn_on[[pc_col]]))

cat("    Missing:  ", format(n_miss, big.mark = ","), "\n")
cat("    Valid:    ", format(n_valid, big.mark = ","), "\n")
cat("    Distinct: ", format(n_uniq, big.mark = ","), "\n")

if ("latitude" %in% names(gn_on) && "longitude" %in% names(gn_on)) {
  cat("    Lat range:", round(min(gn_on$latitude, na.rm = TRUE), 3),
      "to", round(max(gn_on$latitude, na.rm = TRUE), 3), "\n")
  cat("    Lon range:", round(min(gn_on$longitude, na.rm = TRUE), 3),
      "to", round(max(gn_on$longitude, na.rm = TRUE), 3), "\n")
}

top_pc <- gn_on %>%
  mutate(.pc = normalize_pc(.data[[pc_col]])) %>%
  filter(grepl(PC_REGEX, .pc, perl = TRUE)) %>%
  count(.pc, sort = TRUE) %>%
  slice_head(n = 10)
cat("    Top 10 postal codes by place-name count:\n")
print(top_pc)

# ---------------------------------------------------------------------------
# 5. Manifest
# ---------------------------------------------------------------------------
cat("\n[5] Writing manifest to", manifest, "\n")
manifest_lines <- c(
  '{',
  '  "source": "geonames_ca",',
  paste0('  "url": "', GEONAMES_URL, '",'),
  paste0('  "retrieval_date": "', Sys.Date(), '",'),
  paste0('  "sha256": "', sha256, '",'),
  paste0('  "file_size_bytes": ', file_size, ','),
  paste0('  "total_rows": ', nrow(gn_raw), ','),
  paste0('  "ontario_rows_fsa": ', nrow(gn_on), ','),
  paste0('  "valid_pc": ', n_valid, ','),
  paste0('  "distinct_pc": ', n_uniq),
  '}'
)
writeLines(manifest_lines, manifest)
cat("=== GeoNames profile done ===\n")
