# scripts/m1_nar_profile.R
#
# M1 NAR Profiling Proof of Concept
# Open Postal Code Conversion (OPCC)
#
# PURPOSE:
#   Download the Statistics Canada National Address Register (NAR, catalogue
#   46-26-0002, release June 2026), extract Ontario records, profile postal-
#   code completeness and validity, assign to Dissemination Blocks via the
#   Geographic Attribute File, derive higher geographies, emit a quality
#   report, and write a JSON manifest.
#
# DEPENDENCIES: base R, readr, dplyr, jsonlite, digest
#   install.packages(c("readr", "dplyr", "jsonlite", "digest"))
#
# OUTPUTS: console log + JSON manifest in .scratch/m1_nar/
#   Downloaded data go to .scratch/m1_nar/ which is gitignored. Never commit.
#
# LICENCE: NAR is Open Government Licence - Canada (OGL-Canada).
#   Describe postal fields as "observed postal associations" only -- never as
#   authoritative Canada Post assignments.
#
# ASCII-ONLY: no smart quotes, em-dashes, or non-ASCII characters.

library(readr)
library(dplyr)
library(jsonlite)

# ---------------------------------------------------------------------------
# 0. Configuration
# ---------------------------------------------------------------------------

NAR_URL <- "https://www150.statcan.gc.ca/n1/pub/46-26-0002/2022001/202606.zip"
NAR_RELEASE <- "2026-06-26"
NAR_CATALOGUE <- "46-26-0002"

# Ontario province filter candidates (checked against actual column values)
PROVINCE_FILTER_CANDIDATES <- c("ON", "35", "Ontario", "on")

# Ontario FSA prefix fallback (K, L, M, N, P)
ONTARIO_FSA_REGEX <- "^[KLMNP]"

# Postal code regex (normalized ANA NAN format)
PC_REGEX <- "^[A-Z][0-9][A-Z] [0-9][A-Z][0-9]$"

# Gitignored scratch directory
SCRATCH_DIR <- file.path(getwd(), ".scratch", "m1_nar")
if (!dir.exists(SCRATCH_DIR)) dir.create(SCRATCH_DIR, recursive = TRUE)

MANIFEST_PATH <- file.path(SCRATCH_DIR, "m1_nar_manifest.json")
RUN_TIMESTAMP <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

cat("=== M1 NAR Profiling PoC ===\n")
cat("Timestamp:", RUN_TIMESTAMP, "\n")
cat("Scratch:  ", SCRATCH_DIR, "\n\n")

# ---------------------------------------------------------------------------
# 1. Download NAR release, record provenance
# ---------------------------------------------------------------------------

cat("[1] Downloading NAR release (~1.67 GB, may take a few minutes)...\n")
cat("    URL:", NAR_URL, "\n")

nar_zip <- file.path(SCRATCH_DIR, "202606.zip")

if (file.exists(nar_zip) && file.info(nar_zip)$size > 1e9) {
  cat("    Cached ZIP found, skipping download.\n")
} else {
  dl_start <- proc.time()
  # Use curl with resume (-C -) for reliable large-file download
  exit_code <- system2("curl", args = c("-L", "-C", "-", "-o", shQuote(nar_zip), shQuote(NAR_URL)),
                       stdout = "", stderr = "")
  if (exit_code != 0) stop("curl download failed with exit code ", exit_code)
  dl_elapsed <- proc.time() - dl_start
  cat("    Downloaded in", round(dl_elapsed["elapsed"], 1), "s\n")
}

file_size_bytes <- file.info(nar_zip)$size
cat("    File size:", format(file_size_bytes / 1e9, digits = 3), "GB\n")

sha256 <- digest::digest(nar_zip, algo = "sha256", file = TRUE)
cat("    SHA-256:", sha256, "\n")

zip_contents <- unzip(nar_zip, list = TRUE)
cat("    ZIP contents:\n")
print(zip_contents[, c("Name", "Length")], row.names = FALSE)

# ---------------------------------------------------------------------------
# 2. Read NAR file, detect format, log schema
# ---------------------------------------------------------------------------

cat("\n[2] Reading NAR Ontario files (province code 35)...\n")

# NAR ZIP is partitioned by province: Addresses/Address_35_part_N.csv for Ontario
all_csv <- zip_contents$Name[grepl("\\.csv$", zip_contents$Name, ignore.case = TRUE)]
on_csv  <- all_csv[grepl("Address_35_", all_csv)]

if (length(on_csv) == 0) {
  stop("No Ontario (Address_35_*) CSV files found. ZIP structure may have changed.")
}
cat("    Ontario part files found:", length(on_csv), "\n")
cat("    Parts:", paste(basename(on_csv), collapse = ", "), "\n")

# Extract any parts not yet on disk
for (f in on_csv) {
  dest <- file.path(SCRATCH_DIR, f)
  if (!file.exists(dest)) {
    cat("    Extracting", basename(f), "...\n")
    unzip(nar_zip, files = f, exdir = SCRATCH_DIR)
  } else {
    cat("    Cached:", basename(f), "\n")
  }
}

# Read and bind all Ontario parts
cat("    Reading and binding Ontario parts...\n")
nar_raw <- dplyr::bind_rows(lapply(file.path(SCRATCH_DIR, on_csv), function(p) {
  cat("      Reading", basename(p), "...\n")
  readr::read_csv(p, show_col_types = FALSE)
}))

total_rows       <- nrow(nar_raw)
schema_col_names <- names(nar_raw)
schema_col_types <- sapply(nar_raw, function(x) class(x)[1])

cat("    Total Ontario rows:", format(total_rows, big.mark = ","), "\n")
cat("    Columns (", length(schema_col_names), "):\n")
print(data.frame(column = schema_col_names, type = schema_col_types), row.names = FALSE)

# ---------------------------------------------------------------------------
# 3. Extract Ontario rows
# ---------------------------------------------------------------------------

cat("\n[3] Ontario scope verification...\n")
# Data is already Ontario-only (Address_35_* files). Verify via PROV_CODE.
province_col <- intersect(c("PROV_CODE", "MAIL_PROV_ABVN"), schema_col_names)
if (length(province_col) > 0) {
  province_col <- province_col[1]
  prov_vals    <- unique(nar_raw[[province_col]])
  cat("    Province column:", province_col,
      "| Unique values:", paste(prov_vals, collapse = ", "), "\n")
  if (!all(prov_vals %in% c("35", "ON"))) {
    cat("    WARNING: non-Ontario province codes present:", paste(prov_vals, collapse = ", "), "\n")
  }
}
nar_on               <- nar_raw
ontario_rows         <- nrow(nar_on)
province_filter_used <- "Address_35_* part files (Ontario province code 35)"
cat("    Ontario rows:", format(ontario_rows, big.mark = ","), "\n")

# ---------------------------------------------------------------------------
# 4. Profile postal-code completeness and validity
# ---------------------------------------------------------------------------

cat("\n[4] Profiling postal-code completeness and validity...\n")

pc_col_candidates <- c("MAIL_POSTAL_CODE", "postal_code", "POSTAL_CODE",
                       "postalcode", "PostalCode", "mailing_postal_code",
                       "MAILING_POSTAL_CODE", "pc", "PC", "POSTAL", "postal")
pc_col <- intersect(pc_col_candidates, schema_col_names)

if (length(pc_col) == 0) {
  cat("    FATAL: Postal code column not found. Available columns:\n")
  print(schema_col_names)
  stop("Update pc_col_candidates with the correct column name.")
}
pc_col <- pc_col[1]
cat("    Postal code column:", pc_col, "\n")

normalize_pc <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("[[:space:]]+", "", x)
  x <- ifelse(nchar(x) == 6, paste0(substr(x, 1, 3), " ", substr(x, 4, 6)), x)
  x
}

pc_raw  <- nar_on[[pc_col]]
pc_norm <- normalize_pc(pc_raw)

n_total_on   <- length(pc_raw)
n_not_na     <- sum(!is.na(pc_raw) & nchar(trimws(as.character(pc_raw))) > 0)
n_na         <- n_total_on - n_not_na
missing_rate <- round(100 * n_na / n_total_on, 4)
valid_mask   <- grepl(PC_REGEX, pc_norm, perl = TRUE) & !is.na(pc_norm)
n_valid      <- sum(valid_mask)
n_invalid    <- n_not_na - n_valid
valid_rate   <- round(100 * n_valid / max(n_not_na, 1), 4)
n_unique_pc  <- length(unique(pc_norm[valid_mask]))

cat("    Non-missing:", format(n_not_na, big.mark = ","), "\n")
cat("    Missing:    ", format(n_na, big.mark = ","),
    sprintf("(%.4f%%)\n", missing_rate))
cat("    Valid:      ", format(n_valid, big.mark = ","),
    sprintf("(%.4f%% of non-missing)\n", valid_rate))
cat("    Invalid:    ", format(n_invalid, big.mark = ","), "\n")
cat("    Distinct:   ", format(n_unique_pc, big.mark = ","), "\n")

top_pc <- nar_on %>%
  mutate(.pc = normalize_pc(.data[[pc_col]])) %>%
  filter(grepl(PC_REGEX, .pc, perl = TRUE)) %>%
  count(.pc, sort = TRUE) %>%
  slice_head(n = 10)
cat("    Top 10 postal codes by address count:\n")
print(top_pc)

if (n_invalid > 0) {
  cat("    Sample invalid strings:\n")
  print(head(unique(pc_norm[!valid_mask & !is.na(pc_norm)]), 10))
}

# ---------------------------------------------------------------------------
# 5. Dissemination Block assignment via GAF
# ---------------------------------------------------------------------------

cat("\n[5] Dissemination Block assignment via Geographic Attribute File...\n")

# Check whether NAR includes a geographic identifier
geo_col_candidates <- c("DBUID", "dbuid", "DAUID", "dauid", "db_uid", "da_uid",
                        "dissemination_block", "dissemination_area")
geo_col <- intersect(geo_col_candidates, schema_col_names)

if (length(geo_col) > 0) {
  geo_col <- geo_col[1]
  cat("    Geographic ID column found:", geo_col, "\n")
  cat("    Sample values:\n")
  print(head(unique(nar_on[[geo_col]]), 10))
  cat("    NOTE: GAF join can proceed as a flat CSV join on", geo_col, "\n")
  cat("    GAF catalogue: 92-151-X\n")
  cat("    GAF URL (unconfirmed): https://www12.statcan.gc.ca/census-recensement/2021/geo/aip-pia/attribute-attribs/files-fichiers/2021_92-151_X.zip\n")
  gaf_join_type <- paste0("flat join on ", geo_col)
  db_match_n <- NA_integer_
} else {
  lat_candidates <- c("latitude", "LATITUDE", "lat", "LAT", "y", "Y")
  lon_candidates <- c("longitude", "LONGITUDE", "lon", "LON", "long", "LONG", "x", "X")
  has_coords <- length(intersect(lat_candidates, schema_col_names)) > 0 &&
                length(intersect(lon_candidates, schema_col_names)) > 0
  if (has_coords) {
    cat("    No DBUID/DAUID column found. NAR has coordinates only.\n")
    cat("    DB assignment requires spatial join (sf + 2021 DB boundary file 92-160-X).\n")
    cat("    This is out of scope for this non-spatial script -- STUB.\n")
    gaf_join_type <- "spatial join required (coordinates only)"
  } else {
    cat("    No geographic ID or coordinate columns found.\n")
    cat("    Available columns:\n"); print(schema_col_names)
    gaf_join_type <- "unknown -- column detection failed"
  }
  db_match_n <- NA_integer_
}

# ---------------------------------------------------------------------------
# 6. Higher geography (stub until GAF loaded)
# ---------------------------------------------------------------------------

cat("\n[6] Higher geography derivation: STUB -- awaiting GAF join.\n")

da_match_n  <- NA_integer_
csd_match_n <- NA_integer_
cma_match_n <- NA_integer_

# ---------------------------------------------------------------------------
# 7. Quality report
# ---------------------------------------------------------------------------

cat("\n[7] Quality report\n")
cat(strrep("-", 60), "\n")
cat(sprintf("  Catalogue          : %s\n", NAR_CATALOGUE))
cat(sprintf("  Release            : %s\n", NAR_RELEASE))
cat(sprintf("  Download URL       : %s\n", NAR_URL))
cat(sprintf("  File size          : %.3f GB\n", file_size_bytes / 1e9))
cat(sprintf("  SHA-256            : %s\n", sha256))
cat(sprintf("  Province filter    : %s\n", province_filter_used))
cat(sprintf("  Ontario rows       : %s\n", format(ontario_rows, big.mark = ",")))
cat(sprintf("  Missing postal     : %s (%.4f%%)\n",
            format(n_na, big.mark = ","), missing_rate))
cat(sprintf("  Valid postal       : %s (%.4f%% of non-missing)\n",
            format(n_valid, big.mark = ","), valid_rate))
cat(sprintf("  Invalid postal     : %s\n", format(n_invalid, big.mark = ",")))
cat(sprintf("  Distinct valid PCs : %s\n", format(n_unique_pc, big.mark = ",")))
cat(sprintf("  GAF join type      : %s\n", gaf_join_type))
cat(strrep("-", 60), "\n")

# ---------------------------------------------------------------------------
# 8. JSON manifest
# ---------------------------------------------------------------------------

cat("\n[8] Writing manifest to", MANIFEST_PATH, "...\n")

criteria_met <- list(
  nar_download_recorded    = file.exists(nar_zip),
  ontario_extraction_done  = ontario_rows > 0,
  schema_logged            = length(schema_col_names) > 0,
  postal_completeness_done = !is.na(n_valid),
  gaf_db_assignment_done   = !is.na(db_match_n),
  higher_geography_done    = !is.na(da_match_n),
  provenance_output_done   = TRUE
)
profile_status <- if (all(unlist(criteria_met))) "complete" else "incomplete"

manifest <- list(
  manifest_version   = 1L,
  run_timestamp      = RUN_TIMESTAMP,
  profile_status     = profile_status,
  source = list(
    catalogue_number = NAR_CATALOGUE,
    source_name      = "National Address Register",
    publisher        = "Statistics Canada",
    release_date     = NAR_RELEASE,
    licence          = "Open Government Licence - Canada",
    download_url     = NAR_URL,
    sha256           = sha256,
    file_size_bytes  = file_size_bytes
  ),
  schema = list(
    column_names     = schema_col_names,
    column_types     = as.list(schema_col_types),
    ontario_rows_from_parts = total_rows,
    part_files       = basename(on_csv)
  ),
  ontario_profile = list(
    ontario_rows         = ontario_rows,
    province_filter_used = province_filter_used,
    postal_col_used      = pc_col,
    n_non_missing_pc     = n_not_na,
    n_missing_pc         = n_na,
    missing_pc_rate_pct  = missing_rate,
    n_valid_pc           = n_valid,
    n_invalid_pc         = n_invalid,
    valid_pc_rate_pct    = valid_rate,
    distinct_valid_pc    = n_unique_pc,
    pc_regex_used        = PC_REGEX
  ),
  gaf_profile = list(
    gaf_join_type         = gaf_join_type,
    gaf_catalogue_number  = "92-151-X",
    db_match_n            = db_match_n,
    da_match_n            = da_match_n,
    csd_match_n           = csd_match_n,
    cma_match_n           = cma_match_n
  ),
  exit_criteria = criteria_met,
  notes = paste(
    "Postal associations described as 'observed' per project lineage policy.",
    "GAF join is a stub until NAR geo column is confirmed and GAF downloaded.",
    sep = " "
  )
)

jsonlite::write_json(manifest, path = MANIFEST_PATH, pretty = TRUE, auto_unbox = TRUE)
cat("    Manifest written. profile_status:", profile_status, "\n")
cat("\n=== Done ===\n")
