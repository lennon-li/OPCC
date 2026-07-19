# Internal release index.  URLs become available when their corresponding
# versioned release directories are published on the default branch.
.index <- function() {
  jsonlite::read_json(
    system.file("extdata", "release-index.json", package = "OPCC"),
    simplifyVector = FALSE
  )$m2
}

.point_index <- function() {
  jsonlite::read_json(
    system.file("extdata", "release-index.json", package = "OPCC"),
    simplifyVector = FALSE
  )$points
}

.release_spec <- function(index, vintage) {
  spec <- index[[vintage]]
  if (is.null(spec)) {
    stop(sprintf("Unknown vintage: %s", vintage), call. = FALSE)
  }
  spec
}

.cache_path <- function(kind, vintage, cache_dir, extension) {
  file.path(cache_dir, sprintf("opcc-%s-%s%s", kind, vintage, extension))
}

.download_verified <- function(url, path, sha256, offline) {
  if (!file.exists(path)) {
    if (offline) stop("Release is not cached and offline = TRUE", call. = FALSE)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    utils::download.file(url, path, mode = "wb", quiet = TRUE)
  }
  got <- digest::digest(path, algo = "sha256", file = TRUE)
  if (!identical(tolower(got), tolower(sha256))) {
    stop("Checksum verification failed", call. = FALSE)
  }
  path
}

.read_csv_gz <- function(path) {
  utils::read.csv(gzfile(path), stringsAsFactors = FALSE, colClasses = "character")
}

.coerce_correspondence <- function(x, vintage) {
  numeric_columns <- intersect(
    c("address_weight", "allocation_weight", "confidence", "gn_accuracy"), names(x)
  )
  integer_columns <- intersect(
    c("n_observations", "n_unique_addresses", "n_sources"), names(x)
  )
  for (column in numeric_columns) x[[column]] <- as.numeric(x[[column]])
  for (column in integer_columns) x[[column]] <- as.integer(x[[column]])
  if ("best_link" %in% names(x)) x$best_link <- x$best_link == "TRUE"
  attr(x, "opcc_vintage") <- vintage
  attr(x, "opcc_source") <- "OPCC source-qualified postal-code correspondence"
  x
}

#' Normalize Canadian postal codes
#'
#' @param x A character vector of postal codes.
#' @param strict If `TRUE`, reject any non-missing invalid value instead of
#'   returning `NA` for it.
#' @return A character vector in `A1A 1A1` form.
#' @export
normalize_postal_code <- function(x, strict = FALSE) {
  if (!is.character(x)) x <- as.character(x)
  out <- toupper(gsub("[[:space:]-]", "", trimws(x)))
  ok <- grepl(
    "^[ABCEGHJKLMNPRSTVXY][0-9][ABCEGHJKLMNPRSTVWXYZ][0-9][ABCEGHJKLMNPRSTVWXYZ][0-9]$",
    out
  )
  if (strict && any(!is.na(out) & !ok)) stop("Invalid postal code", call. = FALSE)
  out[!ok] <- NA_character_
  ifelse(is.na(out), NA_character_, paste0(substr(out, 1, 3), " ", substr(out, 4, 6)))
}

#' List supported correspondence release vintages
#' @return A character vector of release vintages.
#' @export
list_vintages <- function() names(.index())

#' Download, cache, and verify a correspondence release
#'
#' @param vintage A value returned by [list_vintages()].
#' @param cache_dir Directory used for verified downloaded files.
#' @param offline Require an already cached verified file.
#' @return A data frame of postal-code-to-DB links.
#' @export
get_correspondence <- function(
    vintage = "2026-06-26",
    cache_dir = tools::R_user_dir("OPCC", "cache"),
    offline = FALSE) {
  spec <- .release_spec(.index(), vintage)
  path <- .download_verified(
    spec$artifact,
    .cache_path("m2", vintage, cache_dir, ".csv.gz"),
    spec$sha256,
    offline
  )
  .coerce_correspondence(.read_csv_gz(path), vintage)
}

#' Look up postal-code-to-geography links
#'
#' All DB links are returned by default.  Set `all_links = FALSE` only when a
#' single best link is specifically needed.
#'
#' @param postal_code Character vector of Canadian postal codes.
#' @param level Geography level, `"DB"` or `"DA"`.
#' @param all_links Whether to retain every allocated DB link.
#' @param correspondence Optional already-loaded correspondence data.
#' @param ... Passed to [get_correspondence()] when `correspondence` is NULL.
#' @return A data frame; unmatched normalized postal codes are stored in its
#'   `unmatched` attribute.
#' @export
pc_to_geo <- function(
    postal_code,
    level = c("DB", "DA"),
    all_links = TRUE,
    correspondence = NULL,
    ...) {
  level <- match.arg(level)
  pcs <- unique(normalize_postal_code(postal_code, strict = TRUE))
  x <- if (is.null(correspondence)) get_correspondence(...) else correspondence
  out <- x[x$postal_code %in% pcs, , drop = FALSE]
  if (!all_links) out <- out[out$best_link, , drop = FALSE]
  if (level == "DA") {
    if (!"DAUID" %in% names(out)) stop("Correspondence has no DAUID column", call. = FALSE)
    out <- out[, setdiff(names(out), "DBUID"), drop = FALSE]
  }
  attr(out, "unmatched") <- setdiff(pcs, unique(out$postal_code))
  out
}

#' Read and verify a release manifest
#'
#' @param vintage A value returned by [list_vintages()].
#' @param cache_dir Directory used for verified downloaded files.
#' @param offline Require an already cached verified file.
#' @return A parsed JSON list.
#' @export
release_manifest <- function(
    vintage = "2026-06-26",
    cache_dir = tools::R_user_dir("OPCC", "cache"),
    offline = FALSE) {
  spec <- .release_spec(.index(), vintage)
  path <- .download_verified(
    spec$manifest,
    .cache_path("m2", vintage, cache_dir, ".manifest.json"),
    spec$manifest_sha256,
    offline
  )
  jsonlite::read_json(path, simplifyVector = TRUE)
}

#' Validate a verified correspondence release
#'
#' @param vintage A value returned by [list_vintages()].
#' @param cache_dir Directory used for verified downloaded files.
#' @param offline Require an already cached verified file.
#' @return Invisibly `TRUE`, or an error describing a failed invariant.
#' @export
validate_release <- function(
    vintage = "2026-06-26",
    cache_dir = tools::R_user_dir("OPCC", "cache"),
    offline = FALSE) {
  x <- get_correspondence(vintage, cache_dir, offline)
  required <- c("postal_code", "DBUID", "DAUID", "best_link", "confidence")
  if (!all(required %in% names(x))) stop("Release is missing required columns", call. = FALSE)
  weight_column <- if ("allocation_weight" %in% names(x)) "allocation_weight" else "address_weight"
  if (!weight_column %in% names(x)) stop("Release has no allocation-weight column", call. = FALSE)
  if (anyDuplicated(x[c("postal_code", "DBUID")])) stop("Duplicate postal-code/DB links", call. = FALSE)
  weights <- tapply(x[[weight_column]], x$postal_code, sum)
  best <- tapply(x$best_link, x$postal_code, sum)
  if (any(!is.finite(weights)) || any(abs(weights - 1) > 1e-8)) {
    stop("Allocation weights do not sum to one", call. = FALSE)
  }
  if (any(best != 1L)) stop("Each postal code must have exactly one best link", call. = FALSE)
  invisible(TRUE)
}

#' Look up source-labeled supplementary GeoNames points
#'
#' @param postal_code Character vector of Canadian postal codes.
#' @param vintage Point-release vintage.
#' @param point_file Optional local gzip CSV file. Supplying this enables fully
#'   offline and air-gapped use.
#' @param cache_dir Directory used for verified downloaded files.
#' @param offline Require an already cached verified file.
#' @return Point records, including DB/DA fields when the point intersects a
#'   2021 Ontario dissemination block.
#' @export
pc_to_point <- function(
    postal_code,
    vintage = "2026-07-19",
    point_file = NULL,
    cache_dir = tools::R_user_dir("OPCC", "cache"),
    offline = FALSE) {
  pcs <- unique(normalize_postal_code(postal_code, strict = TRUE))
  if (is.null(point_file)) {
    spec <- .release_spec(.point_index(), vintage)
    point_file <- .download_verified(
      spec$artifact,
      .cache_path("points", vintage, cache_dir, ".csv.gz"),
      spec$sha256,
      offline
    )
  }
  x <- .read_csv_gz(point_file)
  required <- c("postal_code", "latitude", "longitude", "point_source", "point_method")
  if (!all(required %in% names(x))) stop("Point artifact is missing required columns", call. = FALSE)
  out <- x[x$postal_code %in% pcs & x$point_source == "geonames", , drop = FALSE]
  if ("DAUID_ADIDU" %in% names(out)) names(out)[names(out) == "DAUID_ADIDU"] <- "DAUID"
  attr(out, "unmatched") <- setdiff(pcs, unique(out$postal_code))
  attr(out, "opcc_source") <- "GeoNames supplementary point; not NAR address evidence"
  out
}
