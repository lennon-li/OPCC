.opcc_build_cache <- function(cache_dir) {
  if (is.null(cache_dir)) {
    cache_dir <- file.path(tools::R_user_dir("OPCC", "cache"), "build")
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_dir
}

.download_cached <- function(url, dest, label) {
  if (file.exists(dest) && file.info(dest)$size > 0) {
    message(sprintf("[download] %s: already cached at %s", label, dest))
    return(invisible(dest))
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  message(sprintf("[download] %s: fetching %s", label, url))
  utils::download.file(url, dest, mode = "wb")
  message(sprintf("[download] %s: saved to %s", label, dest))
  invisible(dest)
}

.extract_zip <- function(zip_path, exdir, label) {
  contents <- utils::unzip(zip_path, list = TRUE)
  needed <- contents$Name[!grepl("/$", contents$Name)]
  on_disk <- file.path(exdir, needed)
  missing <- needed[!file.exists(on_disk)]
  if (length(missing) == 0L) {
    message(sprintf("[extract] %s: all files already extracted", label))
    return(invisible(file.path(exdir, needed)))
  }
  message(sprintf("[extract] %s: extracting %d file(s) to %s",
                  label, length(missing), exdir))
  utils::unzip(zip_path, files = missing, exdir = exdir)
  invisible(file.path(exdir, needed))
}

#' Download the Statistics Canada National Address Register
#'
#' Downloads the NAR release zip (~1.6 GB) and extracts the Ontario
#' Address and Location part files. Skips the download if the zip is
#' already cached.
#'
#' @param cache_dir Build cache directory. Defaults to a persistent
#'   user-level directory under `tools::R_user_dir("OPCC", "cache")`.
#' @return Invisibly, the path to the NAR scratch directory containing
#'   the extracted Ontario CSV files.
#' @export
download_nar <- function(cache_dir = NULL) {
  cache <- .opcc_build_cache(cache_dir)
  nar_dir <- file.path(cache, "m1_nar")
  zip_path <- file.path(nar_dir, "202606.zip")
  .download_cached(
    "https://www150.statcan.gc.ca/n1/pub/46-26-0002/2022001/202606.zip",
    zip_path,
    "NAR"
  )
  addr_parts <- paste0("Addresses/Address_35_part_", 1:7, ".csv")
  loc_parts <- paste0("Locations/Location_35_part_", 1:5, ".csv")
  members <- c(addr_parts, loc_parts)
  on_disk <- file.path(nar_dir, members)
  missing <- members[!file.exists(on_disk)]
  if (length(missing) > 0L) {
    message(sprintf("[extract] NAR: extracting %d Ontario part file(s)",
                    length(missing)))
    utils::unzip(zip_path, files = missing, exdir = nar_dir)
  } else {
    message("[extract] NAR: Ontario part files already extracted")
  }
  message(sprintf("[download] NAR: %d address + %d location files in %s",
                  length(addr_parts), length(loc_parts), nar_dir))
  invisible(nar_dir)
}

#' Download GeoNames Canadian postal codes
#'
#' Downloads the GeoNames CA_full.csv.zip and extracts the tab-delimited
#' text file. Skips the download if already cached.
#'
#' @param cache_dir Build cache directory.
#' @return Invisibly, the path to the extracted `CA_full.txt`.
#' @export
download_geonames <- function(cache_dir = NULL) {
  cache <- .opcc_build_cache(cache_dir)
  gn_dir <- file.path(cache, "m1_geonames")
  zip_path <- file.path(gn_dir, "CA_full.csv.zip")
  .download_cached(
    "https://download.geonames.org/export/zip/CA_full.csv.zip",
    zip_path,
    "GeoNames"
  )
  txt_path <- file.path(gn_dir, "CA_full.txt")
  if (!file.exists(txt_path)) {
    message("[extract] GeoNames: extracting CA_full.txt")
    utils::unzip(zip_path, files = "CA_full.txt", exdir = gn_dir)
  } else {
    message("[extract] GeoNames: CA_full.txt already extracted")
  }
  invisible(txt_path)
}

#' Download Statistics Canada 2021 census boundary shapefiles
#'
#' Downloads the province/territory and Dissemination Block boundary
#' shapefiles. Skips downloads if already cached.
#'
#' @param cache_dir Build cache directory.
#' @return Invisibly, a named list with `province` and `db` paths to the
#'   extracted `.shp` files.
#' @export
download_census_boundaries <- function(cache_dir = NULL) {
  cache <- .opcc_build_cache(cache_dir)
  shp_dir <- file.path(cache, "shp")

  pr_zip <- file.path(shp_dir, "lpr_000b21a_e.zip")
  .download_cached(
    paste0("https://www12.statcan.gc.ca/census-recensement/2021/geo/",
           "sip-pis/boundary-limites/files-fichiers/lpr_000b21a_e.zip"),
    pr_zip,
    "Province boundary"
  )
  .extract_zip(pr_zip, shp_dir, "Province boundary")

  db_zip <- file.path(shp_dir, "ldb_000b21a_e.zip")
  .download_cached(
    paste0("https://www12.statcan.gc.ca/census-recensement/2021/geo/",
           "sip-pis/boundary-limites/files-fichiers/ldb_000b21a_e.zip"),
    db_zip,
    "DB boundary"
  )
  .extract_zip(db_zip, shp_dir, "DB boundary")

  list(
    province = file.path(shp_dir, "lpr_000b21a_e.shp"),
    db = file.path(shp_dir, "ldb_000b21a_e.shp")
  )
}

#' Download the Statistics Canada 2021 Geographic Attribute File
#'
#' Downloads the GAF zip and extracts the CSV. Skips if already cached.
#'
#' @param cache_dir Build cache directory.
#' @return Invisibly, the path to the extracted GAF CSV.
#' @export
download_gaf <- function(cache_dir = NULL) {
  cache <- .opcc_build_cache(cache_dir)
  gaf_dir <- file.path(cache, "gaf")
  zip_path <- file.path(gaf_dir, "2021_92-151_X.zip")
  .download_cached(
    paste0("https://www12.statcan.gc.ca/census-recensement/2021/geo/",
           "aip-pia/attribute-attribs/files-fichiers/2021_92-151_X.zip"),
    zip_path,
    "GAF"
  )
  csv_path <- file.path(gaf_dir, "2021_92-151_X.csv")
  if (!file.exists(csv_path)) {
    message("[extract] GAF: extracting 2021_92-151_X.csv")
    contents <- utils::unzip(zip_path, list = TRUE)
    csv_member <- contents$Name[grepl("\\.csv$", contents$Name,
                                      ignore.case = TRUE)]
    if (length(csv_member) == 0L) stop("No CSV found in GAF zip", call. = FALSE)
    utils::unzip(zip_path, files = csv_member[1], exdir = gaf_dir)
    extracted <- file.path(gaf_dir, csv_member[1])
    if (extracted != csv_path) file.rename(extracted, csv_path)
  } else {
    message("[extract] GAF: 2021_92-151_X.csv already extracted")
  }
  invisible(csv_path)
}
