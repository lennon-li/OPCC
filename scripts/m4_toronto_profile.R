# scripts/m4_toronto_profile.R
#
# Profile Toronto One Address Repository (CSV, EPSG:4326)
# Licence: Open Government Licence - Toronto
#   https://open.toronto.ca/open-data-licence/
# Role: conditional-accept (first verified municipal source)
#
# ASCII-only. No spatial packages. Scratch dir is gitignored.

library(readr)
library(dplyr)
library(digest)

TORONTO_URL  <- "https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/abedd8bc-e3dd-4d45-8e69-79165a76e4fa/resource/64d4e54b-738f-4cd9-a9e7-8050fac8a52f/download/address-points-4326.csv"
TORONTO_DATE <- ""  # fill in after download: check Last-Modified header
PC_REGEX     <- "^[A-Z][0-9][A-Z] [0-9][A-Z][0-9]$"

SCRATCH_DIR  <- file.path(getwd(), ".scratch", "m1_toronto")
if (!dir.exists(SCRATCH_DIR)) dir.create(SCRATCH_DIR, recursive = TRUE)

tor_file <- file.path(SCRATCH_DIR, "address-points-4326.csv")
manifest <- file.path(SCRATCH_DIR, "m1_toronto_manifest.json")

cat("=== Toronto One Address Repository Profile ===\n")
cat("URL:", TORONTO_URL, "\n\n")

# ---------------------------------------------------------------------------
# 1. Download
# ---------------------------------------------------------------------------
if (file.exists(tor_file) && file.info(tor_file)$size > 1e5) {
  cat("[1] Cached file found, skipping download.\n")
} else {
  cat("[1] Downloading Toronto address points CSV...\n")
  # Capture Last-Modified header to record release date
  hdr <- system2("curl", args = c("-sI", shQuote(TORONTO_URL)),
                 stdout = TRUE, stderr = "")
  lm  <- grep("last-modified", hdr, ignore.case = TRUE, value = TRUE)
  if (length(lm) > 0) cat("    Last-Modified:", lm[1], "\n")

  exit_code <- system2("curl", args = c("-L", "-o", shQuote(tor_file), shQuote(TORONTO_URL)),
                       stdout = "", stderr = "")
  if (exit_code != 0) stop("curl download failed with exit code ", exit_code)
}

file_size <- file.info(tor_file)$size
sha256    <- digest::digest(tor_file, algo = "sha256", file = TRUE)
cat("    Size:", format(file_size / 1e6, digits = 4), "MB\n")
cat("    SHA-256:", sha256, "\n")

# ---------------------------------------------------------------------------
# 2. Read and inspect schema
# ---------------------------------------------------------------------------
cat("\n[2] Reading CSV (first 5 rows for schema)...\n")
tor_sample <- readr::read_csv(tor_file, n_max = 5, show_col_types = FALSE)
cat("    Columns (", ncol(tor_sample), "):\n")
print(names(tor_sample))

cat("\n[3] Reading full file...\n")
tor_raw <- readr::read_csv(tor_file, show_col_types = FALSE)
cat("    Total rows:", format(nrow(tor_raw), big.mark = ","), "\n")

# ---------------------------------------------------------------------------
# 3. Bounding-box check (all records should be Toronto)
# ---------------------------------------------------------------------------
cat("\n[4] Toronto bounding-box check...\n")
lat_col <- names(tor_raw)[tolower(names(tor_raw)) %in% c("latitude", "lat", "y")][1]
lon_col <- names(tor_raw)[tolower(names(tor_raw)) %in% c("longitude", "lon", "long", "x")][1]
if (!is.na(lat_col) && !is.na(lon_col)) {
  in_bbox <- sum(
    tor_raw[[lat_col]] >= 43.58 & tor_raw[[lat_col]] <= 43.86 &
    tor_raw[[lon_col]] >= -79.64 & tor_raw[[lon_col]] <= -79.12,
    na.rm = TRUE
  )
  cat("    Rows within Toronto bbox:", format(in_bbox, big.mark = ","),
      sprintf("(%.2f%%)\n", 100 * in_bbox / nrow(tor_raw)))
  cat("    Lat range:", round(min(tor_raw[[lat_col]], na.rm = TRUE), 4),
      "to", round(max(tor_raw[[lat_col]], na.rm = TRUE), 4), "\n")
  cat("    Lon range:", round(min(tor_raw[[lon_col]], na.rm = TRUE), 4),
      "to", round(max(tor_raw[[lon_col]], na.rm = TRUE), 4), "\n")
} else {
  cat("    No lat/lon columns found -- check column names above.\n")
}

# ---------------------------------------------------------------------------
# 4. Postal-code profile
# ---------------------------------------------------------------------------
cat("\n[5] Postal-code profile...\n")
pc_candidates <- c("POSTAL_CODE", "postal_code", "PostalCode",
                   "postalcode", "POSTCODE", "post_code", "MAIL_POSTAL_CODE")
pc_col <- intersect(pc_candidates, names(tor_raw))
if (length(pc_col) == 0) {
  cat("    FATAL: Postal code column not found. Columns:\n"); print(names(tor_raw))
  stop("Update pc_candidates with the correct column name.")
}
pc_col <- pc_col[1]
cat("    Postal-code column:", pc_col, "\n")

normalize_pc <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("[[:space:]]+", "", x)
  ifelse(nchar(x) == 6, paste0(substr(x, 1, 3), " ", substr(x, 4, 6)), x)
}

pc_norm   <- normalize_pc(tor_raw[[pc_col]])
n_miss    <- sum(is.na(tor_raw[[pc_col]]) | nchar(trimws(as.character(tor_raw[[pc_col]]))) == 0)
n_valid   <- sum(grepl(PC_REGEX, pc_norm, perl = TRUE), na.rm = TRUE)
n_uniq    <- length(unique(pc_norm[grepl(PC_REGEX, pc_norm, perl = TRUE)]))
miss_pct  <- round(100 * n_miss / nrow(tor_raw), 4)
valid_pct <- round(100 * n_valid / max(nrow(tor_raw) - n_miss, 1), 4)

cat("    Missing:  ", format(n_miss, big.mark = ","),
    sprintf("(%.4f%%)\n", miss_pct))
cat("    Valid:    ", format(n_valid, big.mark = ","),
    sprintf("(%.4f%% of non-missing)\n", valid_pct))
cat("    Distinct: ", format(n_uniq, big.mark = ","), "\n")

# FSA distribution (should all be Toronto: M prefix)
fsa <- substr(pc_norm[grepl(PC_REGEX, pc_norm, perl = TRUE)], 1, 3)
non_m <- sum(!grepl("^M", fsa), na.rm = TRUE)
if (non_m > 0) cat("    WARN:", non_m, "valid postal codes outside Toronto (M) FSA range.\n")

top_pc <- data.frame(pc = pc_norm) %>%
  filter(grepl(PC_REGEX, pc, perl = TRUE)) %>%
  count(pc, sort = TRUE) %>%
  slice_head(n = 10)
cat("    Top 10 postal codes by address count:\n")
print(top_pc)

# ---------------------------------------------------------------------------
# 5. Manifest
# ---------------------------------------------------------------------------
cat("\n[6] Writing manifest to", manifest, "\n")
manifest_lines <- c(
  '{',
  '  "source": "toronto_addresses",',
  paste0('  "url": "', TORONTO_URL, '",'),
  paste0('  "retrieval_date": "', Sys.Date(), '",'),
  paste0('  "sha256": "', sha256, '",'),
  paste0('  "file_size_bytes": ', file_size, ','),
  paste0('  "total_rows": ', nrow(tor_raw), ','),
  paste0('  "postal_col_used": "', pc_col, '",'),
  paste0('  "n_missing_pc": ', n_miss, ','),
  paste0('  "valid_pc": ', n_valid, ','),
  paste0('  "distinct_pc": ', n_uniq),
  '}'
)
writeLines(manifest_lines, manifest)
cat("=== Toronto profile done ===\n")
