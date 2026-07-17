# scripts/m4_oda_profile.R
#
# Profile Statistics Canada Open Database of Addresses, Ontario subset
# Catalogue: 46-26-0001, OGL-Canada
# Role: defer-validation (lineage analysis vs NAR, regression tests)
#
# ASCII-only. No spatial packages. Scratch dir is gitignored.

library(readr)
library(dplyr)
library(digest)

ODA_URL     <- "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_ON_v1.zip"
ODA_RELEASE <- "2021"
ODA_CAT     <- "46-26-0001"
PC_REGEX    <- "^[A-Z][0-9][A-Z] [0-9][A-Z][0-9]$"

SCRATCH_DIR <- file.path(getwd(), ".scratch", "m1_oda")
if (!dir.exists(SCRATCH_DIR)) dir.create(SCRATCH_DIR, recursive = TRUE)

oda_zip  <- file.path(SCRATCH_DIR, "ODA_ON_v1.zip")
manifest <- file.path(SCRATCH_DIR, "m1_oda_manifest.json")

cat("=== ODA Ontario Profile ===\n")
cat("URL:", ODA_URL, "\n\n")

# ---------------------------------------------------------------------------
# 1. Download
# ---------------------------------------------------------------------------
if (file.exists(oda_zip) && file.info(oda_zip)$size > 1e5) {
  cat("[1] Cached zip found, skipping download.\n")
} else {
  cat("[1] Downloading ODA Ontario zip...\n")
  exit_code <- system2("curl", args = c("-L", "-o", shQuote(oda_zip), shQuote(ODA_URL)),
                       stdout = "", stderr = "")
  if (exit_code != 0) stop("curl download failed with exit code ", exit_code)
}

file_size <- file.info(oda_zip)$size
sha256    <- digest::digest(oda_zip, algo = "sha256", file = TRUE)
cat("    Size:", format(file_size / 1e6, digits = 4), "MB\n")
cat("    SHA-256:", sha256, "\n")

# ---------------------------------------------------------------------------
# 2. Inspect ZIP and read CSV
# ---------------------------------------------------------------------------
cat("\n[2] ZIP contents:\n")
zip_list <- unzip(oda_zip, list = TRUE)
print(zip_list[, c("Name", "Length")], row.names = FALSE)

csv_name <- zip_list$Name[grepl("\\.csv$", zip_list$Name, ignore.case = TRUE)]
if (length(csv_name) == 0) stop("No CSV found in zip.")
csv_name <- csv_name[which.max(zip_list$Length[grepl("\\.csv$", zip_list$Name, ignore.case = TRUE)])]
csv_path <- file.path(SCRATCH_DIR, csv_name)
if (!file.exists(csv_path)) unzip(oda_zip, files = csv_name, exdir = SCRATCH_DIR)

oda_raw <- readr::read_csv(csv_path, show_col_types = FALSE)
cat("    Columns (", ncol(oda_raw), "):\n")
print(data.frame(column = names(oda_raw), type = sapply(oda_raw, function(x) class(x)[1])),
      row.names = FALSE)
cat("    Total rows:", format(nrow(oda_raw), big.mark = ","), "\n")

# ---------------------------------------------------------------------------
# 3. Ontario scope (ODA_ON is already Ontario-only; verify)
# ---------------------------------------------------------------------------
cat("\n[3] Ontario scope check...\n")
prov_candidates <- c("province", "PROVINCE", "pr", "PR", "prov", "PROV",
                     "PROV_CODE", "province_code")
prov_col <- intersect(prov_candidates, names(oda_raw))
if (length(prov_col) > 0) {
  prov_col <- prov_col[1]
  cat("    Province column:", prov_col, "\n")
  cat("    Unique values:", paste(unique(oda_raw[[prov_col]]), collapse = ", "), "\n")
} else {
  cat("    No province column; ODA_ON file is Ontario-only by construction.\n")
}
ontario_rows <- nrow(oda_raw)
cat("    Ontario rows:", format(ontario_rows, big.mark = ","), "\n")

# ---------------------------------------------------------------------------
# 4. Postal-code profile
# ---------------------------------------------------------------------------
cat("\n[4] Postal-code profile...\n")
pc_candidates <- c("postal_code", "POSTAL_CODE", "postalcode", "PostalCode",
                   "MAIL_POSTAL_CODE", "mailing_postal_code")
pc_col <- intersect(pc_candidates, names(oda_raw))
if (length(pc_col) == 0) {
  cat("    FATAL: Postal code column not found. Columns:\n"); print(names(oda_raw))
  stop("Update pc_candidates.")
}
pc_col <- pc_col[1]
cat("    Postal-code column:", pc_col, "\n")

normalize_pc <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("[[:space:]]+", "", x)
  ifelse(nchar(x) == 6, paste0(substr(x, 1, 3), " ", substr(x, 4, 6)), x)
}

pc_norm  <- normalize_pc(oda_raw[[pc_col]])
n_miss   <- sum(is.na(oda_raw[[pc_col]]) | nchar(trimws(as.character(oda_raw[[pc_col]]))) == 0)
n_valid  <- sum(grepl(PC_REGEX, pc_norm, perl = TRUE), na.rm = TRUE)
n_uniq   <- length(unique(pc_norm[grepl(PC_REGEX, pc_norm, perl = TRUE)]))
miss_pct <- round(100 * n_miss / nrow(oda_raw), 4)
valid_pct <- round(100 * n_valid / max(nrow(oda_raw) - n_miss, 1), 4)

cat("    Missing:  ", format(n_miss, big.mark = ","),
    sprintf("(%.4f%%)\n", miss_pct))
cat("    Valid:    ", format(n_valid, big.mark = ","),
    sprintf("(%.4f%% of non-missing)\n", valid_pct))
cat("    Distinct: ", format(n_uniq, big.mark = ","), "\n")

top_pc <- oda_raw %>%
  mutate(.pc = normalize_pc(.data[[pc_col]])) %>%
  filter(grepl(PC_REGEX, .pc, perl = TRUE)) %>%
  count(.pc, sort = TRUE) %>%
  slice_head(n = 10)
cat("    Top 10 postal codes:\n")
print(top_pc)

# ---------------------------------------------------------------------------
# 5. Provider column (ODA-specific: which municipal source each record came from)
# ---------------------------------------------------------------------------
cat("\n[5] Provider breakdown (ODA lineage)...\n")
prov_data_col <- intersect(c("provider", "PROVIDER", "source", "SOURCE"), names(oda_raw))
if (length(prov_data_col) > 0) {
  prov_data_col <- prov_data_col[1]
  cat("    Provider column:", prov_data_col, "\n")
  print(sort(table(oda_raw[[prov_data_col]]), decreasing = TRUE))
} else {
  cat("    No provider column found.\n")
}

# ---------------------------------------------------------------------------
# 6. CSD identifiers (for NAR join)
# ---------------------------------------------------------------------------
cat("\n[6] CSD identifier check...\n")
csd_candidates <- c("csduid", "CSDUID", "csd_uid", "CSD_UID")
csd_col <- intersect(csd_candidates, names(oda_raw))
if (length(csd_col) > 0) {
  csd_col <- csd_col[1]
  cat("    CSD column:", csd_col,
      "| Distinct CSDs:", length(unique(oda_raw[[csd_col]])), "\n")
} else {
  cat("    No CSDUID column found -- join to NAR via postal_code or lat/lon only.\n")
}

# ---------------------------------------------------------------------------
# 7. Manifest
# ---------------------------------------------------------------------------
cat("\n[7] Writing manifest to", manifest, "\n")
manifest_lines <- c(
  '{',
  paste0('  "source": "', ODA_CAT, '",'),
  paste0('  "url": "', ODA_URL, '",'),
  paste0('  "release": "', ODA_RELEASE, '",'),
  paste0('  "sha256": "', sha256, '",'),
  paste0('  "file_size_bytes": ', file_size, ','),
  paste0('  "ontario_rows": ', ontario_rows, ','),
  paste0('  "postal_col_used": "', pc_col, '",'),
  paste0('  "n_missing_pc": ', n_miss, ','),
  paste0('  "valid_pc": ', n_valid, ','),
  paste0('  "distinct_pc": ', n_uniq),
  '}'
)
writeLines(manifest_lines, manifest)
cat("=== ODA profile done ===\n")
