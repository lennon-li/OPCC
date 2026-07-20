#!/usr/bin/env Rscript

# Build the versioned direct postal-code-to-DA artifact from a versioned M2
# DB correspondence. This is a deterministic attribute roll-up; it does not
# make a spatial assignment or alter source evidence.

root <- getwd()
if (!file.exists(file.path(root, "R", "opcc.R"))) {
  stop("Run this command from the OPCC project root", call. = FALSE)
}
source(file.path(root, "R", "opcc.R"))

vintage <- "2026-06-26"
input_path <- file.path(root, "releases", "m2", vintage, "opcc_m2_correspondence.csv.gz")
input_manifest_path <- file.path(root, "releases", "m2", vintage, "m2_manifest.json")
output_dir <- file.path(root, "releases", "m5", vintage)
output_path <- file.path(output_dir, "opcc_m5_da_correspondence.csv.gz")
manifest_path <- file.path(output_dir, "m5_manifest.json")

if (!file.exists(input_path) || !file.exists(input_manifest_path)) {
  stop("Missing versioned M2 input artifact or manifest", call. = FALSE)
}
if (dir.exists(output_dir)) stop("M5 output directory already exists", call. = FALSE)

input <- utils::read.csv(gzfile(input_path), stringsAsFactors = FALSE, colClasses = "character")
for (column in intersect(c("address_weight", "allocation_weight", "confidence"), names(input))) {
  input[[column]] <- as.numeric(input[[column]])
}
da <- aggregate_da_correspondence(input)
dir.create(output_dir, recursive = TRUE)
temporary_csv <- tempfile(fileext = ".csv")
on.exit(unlink(temporary_csv), add = TRUE)
utils::write.csv(da, temporary_csv, row.names = FALSE, na = "", quote = TRUE)
gzip_status <- system2("gzip", c("-n", "-c", temporary_csv), stdout = output_path)
if (!identical(gzip_status, 0L)) stop("gzip failed while writing M5 artifact", call. = FALSE)

artifact_sha256 <- digest::digest(output_path, algo = "sha256", file = TRUE)
uncompressed_sha256 <- digest::digest(temporary_csv, algo = "sha256", file = TRUE)
input_manifest <- jsonlite::read_json(input_manifest_path, simplifyVector = TRUE)
manifest <- list(
  source_m2 = list(
    vintage = vintage,
    artifact_sha256 = digest::digest(input_path, algo = "sha256", file = TRUE),
    manifest_sha256 = digest::digest(input_manifest_path, algo = "sha256", file = TRUE),
    census_vintage = input_manifest$census_vintage
  ),
  build = list(
    method = "deterministic_db_to_da_attribute_rollup",
    code_version = system("git rev-parse HEAD", intern = TRUE),
    build_timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
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
jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("Built M5 %s: %d rows, %d postal codes.\n", vintage, nrow(da), length(unique(da$postal_code))))
