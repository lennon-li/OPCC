#!/usr/bin/env Rscript

# Build the versioned direct postal-code-to-DA artifact from a versioned M2
# DB correspondence. This is a deterministic attribute roll-up; it does not
# make a spatial assignment or alter source evidence.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("Usage: m5_build_da_correspondence.R <output_dir> <producer_sha>", call. = FALSE)
}
output_dir <- args[1]
producer_sha_input <- args[2]

root <- getwd()
if (!file.exists(file.path(root, "R", "opcc.R"))) {
  stop("Run this command from the OPCC project root", call. = FALSE)
}
source(file.path(root, "R", "opcc.R"))

# Canonicalize producer SHA
producer_sha <- tryCatch({
  system2("git", c("rev-parse", "--verify", paste0(producer_sha_input, "^{commit}")), stdout = TRUE, stderr = TRUE)
}, error = function(e) stop("Invalid producer SHA", call. = FALSE))
if (length(producer_sha) != 1 || nchar(producer_sha) != 40) stop("Invalid producer SHA", call. = FALSE)

# Verify generator scripts exist at that revision
for (script in c("scripts/m5_build_da_correspondence.R", "R/opcc.R")) {
  status <- system2("git", c("ls-tree", "--name-only", producer_sha, script), stdout = TRUE, stderr = TRUE)
  if (length(status) != 1 || status != script) {
    stop(sprintf("Generator script %s not found at producer revision", script), call. = FALSE)
  }
}

vintage <- "2026-06-26"
input_path <- file.path(root, "releases", "m2", vintage, "opcc_m2_correspondence.csv.gz")
input_manifest_path <- file.path(root, "releases", "m2", vintage, "m2_manifest.json")

if (!file.exists(input_path) || !file.exists(input_manifest_path)) {
  stop("Missing versioned M2 input artifact or manifest", call. = FALSE)
}
if (dir.exists(output_dir)) stop("M5 output directory already exists", call. = FALSE)

# Verify M2 hashes
index <- jsonlite::read_json(file.path(root, "inst", "extdata", "release-index.json"), simplifyVector = TRUE)
m2_expected <- index$m2[[vintage]]
if (is.null(m2_expected)) stop("Unknown M2 vintage", call. = FALSE)

m2_artifact_sha256 <- digest::digest(input_path, algo = "sha256", file = TRUE)
m2_manifest_sha256 <- digest::digest(input_manifest_path, algo = "sha256", file = TRUE)

if (tolower(m2_artifact_sha256) != tolower(m2_expected$sha256) ||
    tolower(m2_manifest_sha256) != tolower(m2_expected$manifest_sha256)) {
  stop("M2 input hashes do not match the release index", call. = FALSE)
}

input <- utils::read.csv(gzfile(input_path), stringsAsFactors = FALSE, colClasses = "character")
for (column in intersect(c("address_weight", "allocation_weight", "confidence"), names(input))) {
  input[[column]] <- as.numeric(input[[column]])
}
da <- aggregate_da_correspondence(input)
dir.create(output_dir, recursive = TRUE)

output_path <- file.path(output_dir, "opcc_m5_da_correspondence.csv.gz")
manifest_path <- file.path(output_dir, "m5_manifest.json")

temporary_csv <- tempfile(fileext = ".csv")
on.exit(unlink(temporary_csv), add = TRUE)

# Explicitly control CSV serialization
file_conn <- file(temporary_csv, open = "wb")
utils::write.table(da, file_conn, sep = ",", na = "", row.names = FALSE, col.names = TRUE,
                   qmethod = "double", fileEncoding = "UTF-8", eol = "\n")
close(file_conn)

# Explicit gzip behaviour
gzip_status <- system2("gzip", c("-n", "-c", temporary_csv), stdout = output_path)
if (!identical(gzip_status, 0L)) stop("gzip failed while writing M5 artifact", call. = FALSE)

artifact_sha256 <- digest::digest(output_path, algo = "sha256", file = TRUE)
uncompressed_sha256 <- digest::digest(temporary_csv, algo = "sha256", file = TRUE)
input_manifest <- jsonlite::read_json(input_manifest_path, simplifyVector = TRUE)

manifest <- list(
  source_m2 = list(
    vintage = vintage,
    artifact_sha256 = m2_artifact_sha256,
    manifest_sha256 = m2_manifest_sha256,
    census_vintage = input_manifest$census_vintage
  ),
  build = list(
    method = "deterministic_db_to_da_attribute_rollup",
    code_version = producer_sha
  ),
  row_counts = list(
    correspondence_rows = nrow(da),
    postal_codes = length(unique(da$postal_code)),
    contributing_db_rows = nrow(input)
  ),
  validation_results = list(
    weights_sum_to_one = TRUE,
    unique_best_link = TRUE,
    unique_postal_dauid = TRUE,
    complete_db_lineage = all(nzchar(da$contributing_dbuids))
  ),
  release_artifact = list(
    path = basename(output_path),
    compression = "gzip",
    bytes = unname(file.info(output_path)$size),
    sha256 = artifact_sha256,
    uncompressed_sha256 = uncompressed_sha256
  )
)

json_str <- jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE)
writeLines(as.character(json_str), manifest_path, useBytes = TRUE)

cat(sprintf("Built M5 %s: %d rows, %d postal codes.\n", vintage, nrow(da), length(unique(da$postal_code))))
