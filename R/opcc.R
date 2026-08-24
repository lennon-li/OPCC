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

.da_index <- function() {
  jsonlite::read_json(
    system.file("extdata", "release-index.json", package = "OPCC"),
    simplifyVector = FALSE
  )$m5
}

.centroid_index <- function() {
  jsonlite::read_json(
    system.file("extdata", "release-index.json", package = "OPCC"),
    simplifyVector = FALSE
  )$m1_centroids
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

.opcc_cache_limit <- 64 * 1024^2

.opcc_cache_files <- function(cache_dir) {
  paths <- list.files(cache_dir, full.names = TRUE, no.. = TRUE)
  paths <- paths[basename(paths) |> startsWith("opcc-")]
  info <- file.info(paths)
  paths[!is.na(info$isdir) & !info$isdir]
}

.prune_opcc_cache <- function(cache_dir, preserve = character(),
                              max_bytes = .opcc_cache_limit) {
  files <- .opcc_cache_files(cache_dir)
  sizes <- file.info(files)$size
  total <- sum(sizes, na.rm = TRUE)
  removable <- setdiff(files, preserve)
  removable <- removable[order(file.info(removable)$mtime)]
  for (path in removable) {
    if (total <= max_bytes) break
    size <- file.info(path)$size
    if (unlink(path) == 0L) total <- total - size
  }
  invisible(NULL)
}

#' Clear the downloaded OPCC release cache
#'
#' Removes only OPCC files named `opcc-*` from `cache_dir`. This is an explicit
#' maintenance action; routine downloads retain a small, verified cache capped
#' at 64 MiB.
#'
#' @param cache_dir Directory containing downloaded OPCC release artifacts.
#' @return The paths removed, invisibly.
#' @examples
#' cache <- tempfile("opcc-cache")
#' dir.create(cache)
#' clear_opcc_cache(cache)
#' @export
clear_opcc_cache <- function(cache_dir = tools::R_user_dir("OPCC", "cache")) {
  if (!is.character(cache_dir) || length(cache_dir) != 1L ||
      is.na(cache_dir) || !nzchar(cache_dir)) {
    stop("cache_dir must be a single non-empty character path", call. = FALSE)
  }
  files <- .opcc_cache_files(cache_dir)
  removed <- files[vapply(files, unlink, integer(1)) == 0L]
  invisible(removed)
}

.ontario_bounds <- c(
  latitude_min = 41.6,
  latitude_max = 56.9,
  longitude_min = -95.2,
  longitude_max = -74.3
)

.download_verified <- function(url, path, sha256, offline,
                               downloader = utils::download.file,
                               cache_limit = .opcc_cache_limit) {
  verified <- function(file) {
    identical(tolower(digest::digest(file, algo = "sha256", file = TRUE)),
              tolower(sha256))
  }
  if (file.exists(path) && verified(path)) {
    .prune_opcc_cache(dirname(path), preserve = path, max_bytes = cache_limit)
    return(path)
  }
  if (offline) {
    if (file.exists(path)) stop("Checksum verification failed", call. = FALSE)
    stop("Release is not cached and offline = TRUE", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(paste0(basename(path), "."), tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  # CRAN policy: fail gracefully when a remote resource is unavailable.
  # Only errors are converted here: a partial or corrupt payload is caught by
  # the checksum below, and download.file() can warn on a transfer that still
  # succeeds.
  tryCatch(
    downloader(url, temporary, mode = "wb", quiet = TRUE),
    error = function(e) {
      stop("Could not download the release artifact.\n  URL: ", url,
           "\n  Reason: ", conditionMessage(e),
           "\nCheck your network connection, or use a cached release with ",
           "offline = TRUE.", call. = FALSE)
    }
  )
  if (!file.exists(temporary) || !verified(temporary)) {
    stop("Checksum verification failed", call. = FALSE)
  }
  if (!file.rename(temporary, path)) {
    stop("Could not promote verified download into the cache", call. = FALSE)
  }
  .prune_opcc_cache(dirname(path), preserve = path, max_bytes = cache_limit)
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

.coerce_da_correspondence <- function(x, vintage) {
  numeric_columns <- intersect(c("allocation_weight"), names(x))
  integer_columns <- intersect(c("n_contributing_dbs"), names(x))
  for (column in numeric_columns) x[[column]] <- as.numeric(x[[column]])
  for (column in integer_columns) x[[column]] <- as.integer(x[[column]])
  if ("best_link" %in% names(x)) x$best_link <- x$best_link == "TRUE"
  character_columns <- intersect(
    c("source_vintages", "census_vintages", "evidence_classes"), names(x)
  )
  for (column in character_columns) x[[column]][!nzchar(x[[column]])] <- NA_character_
  attr(x, "opcc_vintage") <- vintage
  attr(x, "opcc_source") <- "OPCC direct postal-code-to-DA correspondence"
  x
}

.collapse_values <- function(x) paste(sort(unique(as.character(x))), collapse = "|")

#' Aggregate postal-code-to-DB evidence to DA links
#'
#' @param correspondence A postal-code-to-DB correspondence data frame.
#' @return A data frame with one row per `postal_code` and `DAUID`.
#' @examples
#' # A small in-line postal-code-to-DB evidence table.  Allocation weights
#' # must sum to one within each postal code.
#' db_links <- data.frame(
#'   postal_code = c("M5V 3A8", "M5V 3A8", "M5V 3A8"),
#'   DBUID = c("35200001000", "35200001001", "35200002000"),
#'   DAUID = c("35200001", "35200001", "35200002"),
#'   allocation_weight = c(0.5, 0.25, 0.25),
#'   source_vintage = "2026-06-26",
#'   census_vintage = "2021",
#'   evidence_class = "NAR",
#'   stringsAsFactors = FALSE
#' )
#' aggregate_da_correspondence(db_links)
#'
#' @export
aggregate_da_correspondence <- function(correspondence) {
  required <- c("postal_code", "DBUID", "DAUID")
  if (!all(required %in% names(correspondence))) {
    stop("Correspondence is missing postal_code, DBUID, or DAUID", call. = FALSE)
  }
  weight_column <- if ("allocation_weight" %in% names(correspondence)) {
    "allocation_weight"
  } else if ("address_weight" %in% names(correspondence)) {
    "address_weight"
  } else {
    stop("Correspondence has no allocation-weight column", call. = FALSE)
  }
  x <- correspondence
  x$postal_code <- as.character(x$postal_code)
  x$DBUID <- as.character(x$DBUID)
  x$DAUID <- as.character(x$DAUID)
  x[[weight_column]] <- as.numeric(x[[weight_column]])
  if (anyNA(x$postal_code) || anyNA(x$DBUID) || anyNA(x$DAUID) ||
      any(!nzchar(x$postal_code) | !nzchar(x$DBUID) | !nzchar(x$DAUID))) {
    stop("Correspondence has missing identifiers", call. = FALSE)
  }
  if (any(!is.finite(x[[weight_column]])) || any(x[[weight_column]] < 0)) {
    stop("Correspondence has invalid allocation weights", call. = FALSE)
  }
  if (anyDuplicated(x[c("postal_code", "DBUID")])) {
    stop("Duplicate postal-code/DB links", call. = FALSE)
  }
  input_weights <- tapply(x[[weight_column]], x$postal_code, sum)
  if (any(abs(input_weights - 1) > 1e-8)) {
    stop("Input allocation weights do not sum to one", call. = FALSE)
  }
  x <- x[order(x$postal_code, x$DAUID, x$DBUID), , drop = FALSE]
  group_start <- c(TRUE, x$postal_code[-1L] != x$postal_code[-nrow(x)] |
    x$DAUID[-1L] != x$DAUID[-nrow(x)])
  groups <- cumsum(group_start)
  starts <- which(group_start)
  ends <- c(starts[-1L] - 1L, nrow(x))
  output <- data.frame(
    postal_code = x$postal_code[starts],
    DAUID = x$DAUID[starts],
    allocation_weight = as.numeric(rowsum(x[[weight_column]], groups, reorder = FALSE)),
    n_contributing_dbs = ends - starts + 1L,
    contributing_dbuids = vapply(seq_along(starts), function(i) {
      paste(x$DBUID[starts[[i]]:ends[[i]]], collapse = "|")
    }, character(1)),
    source_vintages = vapply(seq_along(starts), function(i) {
      if (!"source_vintage" %in% names(x)) return(NA_character_)
      .collapse_values(x$source_vintage[starts[[i]]:ends[[i]]])
    }, character(1)),
    census_vintages = vapply(seq_along(starts), function(i) {
      if (!"census_vintage" %in% names(x)) return(NA_character_)
      .collapse_values(x$census_vintage[starts[[i]]:ends[[i]]])
    }, character(1)),
    evidence_classes = vapply(seq_along(starts), function(i) {
      if (!"evidence_class" %in% names(x)) return(NA_character_)
      .collapse_values(x$evidence_class[starts[[i]]:ends[[i]]])
    }, character(1)),
    stringsAsFactors = FALSE
  )
  winner_order <- order(output$postal_code, -output$allocation_weight, output$DAUID)
  output$best_link <- FALSE
  output$best_link[winner_order[!duplicated(output$postal_code[winner_order])]] <- TRUE
  output <- output[order(output$postal_code, -output$allocation_weight, output$DAUID), , drop = FALSE]
  rownames(output) <- NULL
  output_weights <- tapply(output$allocation_weight, output$postal_code, sum)
  output_best <- tapply(output$best_link, output$postal_code, sum)
  if (any(abs(output_weights - 1) > 1e-8) || any(output_best != 1L)) {
    stop("DA roll-up invariants failed", call. = FALSE)
  }
  output
}

#' Normalize Canadian postal codes
#'
#' @param x A character vector of postal codes.
#' @param strict If `TRUE`, reject any non-missing invalid value instead of
#'   returning `NA` for it.
#' @return A character vector in `A1A 1A1` form.
#' @examples
#' normalize_postal_code(c("m5v3a8", "M5V 3A8", "M5V-3A8"))
#'
#' # Invalid values become NA unless strict = TRUE, which raises an error.
#' normalize_postal_code(c("M5V 3A8", "not a postal code"))
#' try(normalize_postal_code("not a postal code", strict = TRUE))
#'
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
#'
#' @param level Geography level, `"DB"` or `"DA"`.
#' @return A character vector of release vintages.
#' @examples
#' list_vintages("DB")
#' list_vintages("DA")
#'
#' @export
list_vintages <- function(level = c("DB", "DA")) {
  level <- match.arg(level)
  names(if (level == "DB") .index() else .da_index())
}

#' Download, cache, and verify a correspondence release
#'
#' @param vintage A value returned by [list_vintages()].
#' @param cache_dir Directory for the small, verified, actively managed
#'   runtime cache.
#' @param offline Require an already cached verified file.
#' @return A data frame of postal-code-to-DB links.
#' @examples
#' list_vintages("DB")
#'
#' # Pass an explicit cache directory; never write to the default user cache
#' # from an example or a test.
#' cache <- tempfile("opcc-cache")
#'
#' \donttest{
#' # Downloads and checksum-verifies a release artifact, so it needs network
#' # access and is not run automatically.
#' if (interactive()) {
#'   m2 <- get_correspondence("2026-06-26", cache_dir = cache)
#'   utils::head(m2[c("postal_code", "DBUID", "DAUID", "allocation_weight")])
#' }
#' }
#'
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

#' Download, cache, and verify a direct DA correspondence release
#'
#' @param vintage A value returned by [list_vintages()] for `level = "DA"`.
#' @param cache_dir Directory for the small, verified, actively managed
#'   runtime cache.
#' @param offline Require an already cached verified file.
#' @return A data frame of postal-code-to-DA links with contributing DB lineage.
#' @examples
#' list_vintages("DA")
#'
#' # Pass an explicit cache directory; never write to the default user cache
#' # from an example or a test.
#' cache <- tempfile("opcc-cache")
#'
#' \donttest{
#' # Downloads and checksum-verifies a release artifact, so it needs network
#' # access and is not run automatically.
#' if (interactive()) {
#'   m5 <- get_da_correspondence("2026-06-26", cache_dir = cache)
#'   utils::head(m5[c("postal_code", "DAUID", "allocation_weight")])
#' }
#' }
#'
#' @export
get_da_correspondence <- function(
    vintage = "2026-06-26",
    cache_dir = tools::R_user_dir("OPCC", "cache"),
    offline = FALSE) {
  spec <- .release_spec(.da_index(), vintage)
  path <- .download_verified(
    spec$artifact,
    .cache_path("m5", vintage, cache_dir, ".csv.gz"),
    spec$sha256,
    offline
  )
  .coerce_da_correspondence(.read_csv_gz(path), vintage)
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
#' @examples
#' # Supplying `correspondence` keeps the lookup fully offline.
#' da_links <- data.frame(
#'   postal_code = c("M5V 3A8", "M5V 3A8"),
#'   DAUID = c("35200001", "35200002"),
#'   allocation_weight = c(0.75, 0.25),
#'   n_contributing_dbs = c(2L, 1L),
#'   contributing_dbuids = c("35200001000|35200001001", "35200002000"),
#'   source_vintages = "2026-06-26",
#'   census_vintages = "2021",
#'   evidence_classes = "NAR",
#'   best_link = c(TRUE, FALSE),
#'   stringsAsFactors = FALSE
#' )
#' pc_to_geo("M5V 3A8", level = "DA", correspondence = da_links)
#'
#' # A single best link, when one is specifically needed.
#' pc_to_geo("m5v3a8", level = "DA", correspondence = da_links,
#'           all_links = FALSE)
#'
#' # Unmatched postal codes stay explicit rather than being dropped silently.
#' found <- pc_to_geo(c("M5V 3A8", "K1A 0A6"), level = "DA",
#'                    correspondence = da_links)
#' attr(found, "unmatched")
#'
#' @export
pc_to_geo <- function(
    postal_code,
    level = c("DB", "DA"),
    all_links = TRUE,
    correspondence = NULL,
    ...) {
  level <- match.arg(level)
  pcs <- unique(normalize_postal_code(postal_code, strict = TRUE))
  x <- if (is.null(correspondence)) {
    if (level == "DA") get_da_correspondence(...) else get_correspondence(...)
  } else {
    correspondence
  }
  if (level == "DA" && !is.null(correspondence) && "DBUID" %in% names(x)) x <- aggregate_da_correspondence(x)
  out <- x[x$postal_code %in% pcs, , drop = FALSE]
  if (!all_links) out <- out[out$best_link, , drop = FALSE]
  attr(out, "unmatched") <- setdiff(pcs, unique(out$postal_code))
  out
}

#' Read and verify a release manifest
#'
#' @param vintage A value returned by [list_vintages()].
#' @param level Geography level, `"DB"` or `"DA"`.
#' @param cache_dir Directory for the small, verified, actively managed
#'   runtime cache.
#' @param offline Require an already cached verified file.
#' @return A parsed JSON list.
#' @examples
#' list_vintages("DB")
#' cache <- tempfile("opcc-cache")
#'
#' \donttest{
#' # Downloads and checksum-verifies the release manifest, so it needs
#' # network access and is not run automatically.
#' if (interactive()) {
#'   manifest <- release_manifest("2026-06-26", cache_dir = cache)
#'   names(manifest)
#' }
#' }
#'
#' @export
release_manifest <- function(
    vintage = "2026-06-26",
    cache_dir = tools::R_user_dir("OPCC", "cache"),
    offline = FALSE,
    level = c("DB", "DA")) {
  level <- match.arg(level)
  spec <- .release_spec(if (level == "DB") .index() else .da_index(), vintage)
  path <- .download_verified(
    spec$manifest,
    .cache_path(if (level == "DB") "m2" else "m5", vintage, cache_dir, ".manifest.json"),
    spec$manifest_sha256,
    offline
  )
  jsonlite::read_json(path, simplifyVector = TRUE)
}

#' Validate a verified correspondence release
#'
#' @param vintage A value returned by [list_vintages()].
#' @param level Geography level, `"DB"` or `"DA"`.
#' @param cache_dir Directory for the small, verified, actively managed
#'   runtime cache.
#' @param offline Require an already cached verified file.
#' @return Invisibly `TRUE`, or an error describing a failed invariant.
#' @examples
#' list_vintages("DB")
#' cache <- tempfile("opcc-cache")
#'
#' \donttest{
#' # Downloads the release and its manifest, so it needs network access and
#' # is not run automatically.
#' if (interactive()) {
#'   validate_release("2026-06-26", cache_dir = cache)
#' }
#' }
#'
#' @export
validate_release <- function(
    vintage = "2026-06-26",
    cache_dir = tools::R_user_dir("OPCC", "cache"),
    offline = FALSE,
    level = c("DB", "DA")) {
  level <- match.arg(level)
  x <- if (level == "DB") {
    get_correspondence(vintage, cache_dir, offline)
  } else {
    get_da_correspondence(vintage, cache_dir, offline)
  }
  manifest <- release_manifest(vintage, cache_dir, offline, level)
  required <- if (level == "DB") {
    c("postal_code", "DBUID", "DAUID", "best_link", "confidence")
  } else {
    c("postal_code", "DAUID", "best_link", "n_contributing_dbs", "contributing_dbuids", "source_vintages")
  }
  if (!all(required %in% names(x))) stop("Release is missing required columns", call. = FALSE)
  weight_column <- if ("allocation_weight" %in% names(x)) "allocation_weight" else "address_weight"
  if (!weight_column %in% names(x)) stop("Release has no allocation-weight column", call. = FALSE)
  key_column <- if (level == "DB") "DBUID" else "DAUID"
  if (anyDuplicated(x[c("postal_code", key_column)])) stop("Duplicate postal-code/geography links", call. = FALSE)
  weights <- tapply(x[[weight_column]], x$postal_code, sum)
  best <- tapply(x$best_link, x$postal_code, sum)
  if (any(!is.finite(weights)) || any(abs(weights - 1) > 1e-8)) {
    stop("Allocation weights do not sum to one", call. = FALSE)
  }
  if (any(best != 1L)) stop("Each postal code must have exactly one best link", call. = FALSE)
  if (!identical(tolower(manifest$release_artifact$sha256),
                 tolower(.release_spec(if (level == "DB") .index() else .da_index(), vintage)$sha256))) {
    stop("Manifest/index disagreement", call. = FALSE)
  }
  invisible(TRUE)
}

#' Look up source-qualified point observations
#'
#' @param postal_code Character vector of Canadian postal codes.
#' @param vintage Point-release vintage.
#' @param point_file Optional local gzip CSV file. Supplying this enables fully
#'   offline and air-gapped use.
#' @param cache_dir Directory for the small, verified, actively managed
#'   runtime cache.
#' @param offline Require an already cached verified file.
#' @param source Optional character vector of `point_source` values to retain.
#'   By default, observations from every source are returned.
#' @return All matching source-qualified point observations, including DB/DA
#'   fields when a point intersects a 2021 Ontario dissemination block.
#' @examples
#' # `point_file` accepts any local gzip CSV with the required columns, which
#' # makes point lookups fully offline and air-gapped.
#' points <- data.frame(
#'   postal_code = c("M5V 3A8", "M5V 3A8"),
#'   latitude = c(43.6426, 43.6430),
#'   longitude = c(-79.3871, -79.3875),
#'   point_source = c("nar", "geonames"),
#'   point_method = c("address_point", "centroid"),
#'   stringsAsFactors = FALSE
#' )
#' point_file <- tempfile("opcc-points", fileext = ".csv.gz")
#' connection <- gzfile(point_file, "w")
#' utils::write.csv(points, connection, row.names = FALSE)
#' close(connection)
#'
#' pc_to_point("M5V 3A8", point_file = point_file)
#'
#' # Restrict the evidence to one source.
#' pc_to_point("M5V 3A8", point_file = point_file, source = "nar")
#'
#' unlink(point_file)
#'
#' @export
pc_to_point <- function(
    postal_code,
    vintage = "2026-07-19",
    point_file = NULL,
    cache_dir = tools::R_user_dir("OPCC", "cache"),
    offline = FALSE,
    source = NULL) {
  pcs <- unique(normalize_postal_code(postal_code, strict = TRUE))
  if (!is.null(source)) {
    valid_source <- is.character(source) && length(source) > 0L &&
      !anyNA(source) && all(nzchar(trimws(source)))
    if (!valid_source) {
      stop(
        "source must contain one or more non-empty point_source values",
        call. = FALSE
      )
    }
    source <- unique(trimws(source))
  }
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
  keep <- x$postal_code %in% pcs
  if (!is.null(source)) keep <- keep & x$point_source %in% source
  out <- x[keep, , drop = FALSE]
  if ("DAUID_ADIDU" %in% names(out)) names(out)[names(out) == "DAUID_ADIDU"] <- "DAUID"
  attr(out, "unmatched") <- setdiff(pcs, unique(out$postal_code))
  attr(out, "opcc_source") <- "OPCC source-qualified point evidence"
  out
}

.load_postal_centroids <- function(vintage = "2026-06-26",
                                   centroid_file = NULL,
                                   cache_dir = tools::R_user_dir("OPCC", "cache"),
                                   offline = FALSE) {
  if (is.null(centroid_file)) {
    spec <- .release_spec(.centroid_index(), vintage)
    centroid_file <- .download_verified(
      spec$artifact,
      .cache_path("m1-centroids", vintage, cache_dir, ".csv.gz"),
      spec$sha256,
      offline
    )
  }
  x <- .read_csv_gz(centroid_file)
  required <- c("postal_code", "latitude", "longitude", "point_source", "point_method")
  if (!all(required %in% names(x))) {
    stop("M1 centroid artifact is missing required columns", call. = FALSE)
  }
  x$latitude <- as.numeric(x$latitude)
  x$longitude <- as.numeric(x$longitude)
  x
}

.postal_centroids <- function(postal_code,
                              vintage = "2026-06-26",
                              centroid_file = NULL,
                              cache_dir = tools::R_user_dir("OPCC", "cache"),
                              offline = FALSE) {
  x <- .load_postal_centroids(vintage, centroid_file, cache_dir, offline)
  .filter_postal_centroids(x, postal_code)
}

.filter_postal_centroids <- function(x, postal_code) {
  pcs <- unique(normalize_postal_code(postal_code, strict = TRUE))
  out <- x[x$postal_code %in% pcs, , drop = FALSE]
  attr(out, "unmatched") <- setdiff(pcs, unique(out$postal_code))
  out
}

.contribution_message <- function() {
  message(
    "This source layer remains local and separate from canonical OPCC releases. ",
    "If redistribution is permitted, submit its contribution bundle as an OPCC issue or pull request."
  )
}

.restricted_source <- function(...) {
  text <- paste(unlist(list(...), use.names = FALSE), collapse = " ")
  grepl("canada[[:space:]-]*post|pccf\\+?", text, ignore.case = TRUE)
}

.check_adapter <- function(adapter) {
  if (!inherits(adapter, "opcc_source_adapter")) {
    stop("adapter must be created by new_source_adapter()", call. = FALSE)
  }
  if (.restricted_source(adapter$source_id, adapter$licence, adapter$lineage)) {
    stop("Canada Post, PCCF, and PCCF+ sources cannot enter OPCC", call. = FALSE)
  }
  invisible(adapter)
}

.adapter_choice <- function(value, field, choices) {
  if (!is.character(value) || length(value) != 1L ||
      is.na(value) || !value %in% choices) {
    stop(
      sprintf("%s must be one of: %s", field, paste(choices, collapse = ", ")),
      call. = FALSE
    )
  }
  value
}

.adapter_label <- function(value, field) {
  if (!is.character(value) || length(value) != 1L ||
      is.na(value) || !nzchar(trimws(value))) {
    stop(sprintf("%s must be a non-empty scalar string", field), call. = FALSE)
  }
  trimws(value)
}

.adapter_spec_value <- function(spec, field) {
  value <- spec[[field]]
  if (is.null(value)) "unknown" else value
}

.json_safe <- function(x) {
  if (inherits(x, "Date")) return(as.character(x))
  if (is.list(x)) return(lapply(x, .json_safe))
  x
}

#' Define a source adapter for a local evidence layer
#'
#' @param source_id Stable, lower-case source identifier.
#' @param licence Licence or permission statement for the source.
#' @param lineage Source lineage and collection method.
#' @param retrieval_date Source retrieval or creation date.
#' @param schema_map Named mapping from OPCC fields to source fields.
#' @param endpoint Optional public retrieval endpoint.
#' @param checksum Optional SHA-256 checksum of the source artifact.
#' @param location_type Source location type: `physical`, `mailing`, or
#'   `unknown`.
#' @param coordinate_method Coordinate derivation method: `address_point`,
#'   `entrance`, `building`, `parcel`, `centroid`, or `unknown`.
#' @param authority_level Source authority classification.
#' @param coverage_type Source coverage classification.
#' @param update_frequency Expected source update frequency.
#' @return An `opcc_source_adapter` object.
#' @examples
#' adapter <- new_source_adapter(
#'   source_id = "example_open_addresses",
#'   licence = "Open Government Licence - Ontario",
#'   lineage = "Municipal open address points, retrieved from a city portal",
#'   retrieval_date = as.Date("2026-01-15"),
#'   schema_map = list(postal_code = "pc", latitude = "lat", longitude = "lon"),
#'   location_type = "physical",
#'   coordinate_method = "address_point"
#' )
#' adapter$source_id
#' adapter$schema_map
#'
#' @export
new_source_adapter <- function(
    source_id,
    licence,
    lineage,
    retrieval_date = Sys.Date(),
    schema_map = list(postal_code = "postal_code"),
    endpoint = NULL,
    checksum = NULL,
    location_type = "unknown",
    coordinate_method = "unknown",
    authority_level = "unknown",
    coverage_type = "unknown",
    update_frequency = "unknown") {
  .contribution_message()
  required <- c(source_id, licence, lineage)
  if (any(lengths(list(source_id, licence, lineage)) != 1L) || any(is.na(required)) ||
      any(!nzchar(trimws(required)))) {
    stop("source_id, licence, and lineage must be non-missing scalar strings", call. = FALSE)
  }
  if (!grepl("^[a-z][a-z0-9_-]*$", source_id)) {
    stop("source_id must use lower-case letters, digits, underscores, or hyphens", call. = FALSE)
  }
  if (.restricted_source(source_id, licence, lineage, endpoint)) {
    stop("Canada Post, PCCF, and PCCF+ sources cannot enter OPCC", call. = FALSE)
  }
  if (!is.list(schema_map) || is.null(names(schema_map)) ||
      !"postal_code" %in% names(schema_map)) {
    stop("schema_map must be a named list containing postal_code", call. = FALSE)
  }
  map_names <- names(schema_map)
  if (anyNA(map_names) || any(!nzchar(trimws(map_names))) ||
      anyDuplicated(map_names)) {
    stop("schema_map must have unique, non-empty canonical field names", call. = FALSE)
  }
  scalar_fields <- vapply(
    schema_map,
    function(field) {
      is.character(field) && length(field) == 1L &&
        !is.na(field) && nzchar(trimws(field))
    },
    logical(1)
  )
  if (!all(scalar_fields)) {
    stop("schema_map values must be non-empty scalar source field names", call. = FALSE)
  }
  source_fields <- unname(unlist(schema_map, use.names = FALSE))
  if (anyDuplicated(source_fields)) {
    stop("schema_map must use unique source fields", call. = FALSE)
  }
  if (!is.null(checksum) && (!is.character(checksum) || length(checksum) != 1L ||
      !grepl("^[0-9a-fA-F]{64}$", checksum))) {
    stop("checksum must be a 64-character SHA-256 hex string", call. = FALSE)
  }
  location_type <- .adapter_choice(
    location_type,
    "location_type",
    c("physical", "mailing", "unknown")
  )
  coordinate_method <- .adapter_choice(
    coordinate_method,
    "coordinate_method",
    c("address_point", "entrance", "building", "parcel", "centroid", "unknown")
  )
  authority_level <- .adapter_label(authority_level, "authority_level")
  coverage_type <- .adapter_label(coverage_type, "coverage_type")
  update_frequency <- .adapter_label(update_frequency, "update_frequency")
  retrieval_date <- tryCatch(
    as.Date(retrieval_date),
    error = function(error) as.Date(NA)
  )
  if (is.na(retrieval_date)) stop("retrieval_date must be a valid date", call. = FALSE)
  structure(
    list(
      source_id = source_id,
      licence = licence,
      lineage = lineage,
      retrieval_date = retrieval_date,
      schema_map = schema_map,
      endpoint = endpoint,
      checksum = checksum,
      location_type = location_type,
      coordinate_method = coordinate_method,
      authority_level = authority_level,
      coverage_type = coverage_type,
      update_frequency = update_frequency
    ),
    class = "opcc_source_adapter"
  )
}

#' Load the versioned GeoNames supplementary-point adapter
#'
#' @return An `opcc_source_adapter` for the packaged GeoNames point artifact.
#' @examples
#' adapter <- geonames_supplementary_adapter()
#' adapter$source_id
#' adapter$coordinate_method
#' adapter$licence
#'
#' @export
geonames_supplementary_adapter <- function() {
  path <- system.file("extdata", "adapters", "geonames-2026-07-19.json", package = "OPCC")
  if (!nzchar(path)) stop("Packaged GeoNames adapter metadata is unavailable", call. = FALSE)
  spec <- jsonlite::read_json(path, simplifyVector = TRUE)
  new_source_adapter(
    source_id = spec$source_id,
    licence = spec$licence,
    lineage = spec$lineage,
    retrieval_date = spec$retrieval_date,
    schema_map = as.list(spec$schema_map),
    endpoint = spec$endpoint,
    checksum = spec$artifact_sha256,
    location_type = .adapter_spec_value(spec, "location_type"),
    coordinate_method = .adapter_spec_value(spec, "coordinate_method"),
    authority_level = .adapter_spec_value(spec, "authority_level"),
    coverage_type = .adapter_spec_value(spec, "coverage_type"),
    update_frequency = .adapter_spec_value(spec, "update_frequency")
  )
}

#' Validate local postal-code evidence
#'
#' @param data A data frame with a postal-code field named by `adapter`.
#' @param adapter Source metadata created by [new_source_adapter()].
#' @param on_invalid How to handle invalid rows: error, drop them, or retain
#'   them in the `opcc_quarantine` attribute.
#' @return A normalized data frame with `postal_code` and validation metadata.
#'   Coordinate-bearing rows outside the inclusive broad Ontario bounds
#'   (latitude 41.6 to 56.9, longitude -95.2 to -74.3) are invalid and counted
#'   in `outside_ontario_bounds_rows`.
#' @examples
#' adapter <- new_source_adapter(
#'   source_id = "example_open_addresses",
#'   licence = "Open Government Licence - Ontario",
#'   lineage = "Municipal open address points, retrieved from a city portal",
#'   retrieval_date = as.Date("2026-01-15"),
#'   schema_map = list(postal_code = "pc", latitude = "lat", longitude = "lon")
#' )
#' raw <- data.frame(
#'   pc = c("m5v3a8", "K1A 0A6", "not a postal code"),
#'   lat = c(43.6426, 45.4215, NA),
#'   lon = c(-79.3871, -75.6972, NA),
#'   stringsAsFactors = FALSE
#' )
#' clean <- validate_source_data(raw, adapter, on_invalid = "quarantine")
#' clean$postal_code
#' attr(clean, "opcc_validation_report")[c("accepted_rows", "rejected_rows")]
#' attr(clean, "opcc_quarantine")$.opcc_validation_reason
#'
#' @export
validate_source_data <- function(
    data,
    adapter,
    on_invalid = c("error", "drop", "quarantine")) {
  .contribution_message()
  .check_adapter(adapter)
  on_invalid <- match.arg(on_invalid)
  if (!is.data.frame(data)) stop("data must be a data frame", call. = FALSE)
  missing_fields <- setdiff(
    unname(unlist(adapter$schema_map, use.names = FALSE)),
    names(data)
  )
  if (length(missing_fields) > 0L) {
    stop(
      sprintf(
        "data is missing mapped source field(s): %s",
        paste(missing_fields, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  out <- data
  for (canonical_field in names(adapter$schema_map)) {
    source_field <- adapter$schema_map[[canonical_field]]
    out[[canonical_field]] <- data[[source_field]]
  }

  raw_postal_code <- as.character(out$postal_code)
  missing_postal <- is.na(raw_postal_code) | !nzchar(trimws(raw_postal_code))
  out$postal_code <- normalize_postal_code(raw_postal_code, strict = FALSE)
  invalid_postal <- !missing_postal & is.na(out$postal_code)

  coordinate_columns <- intersect(c("latitude", "longitude"), names(out))
  if (length(coordinate_columns) == 1L) {
    stop("latitude and longitude must be supplied together", call. = FALSE)
  }
  incomplete_coordinate <- rep(FALSE, nrow(out))
  nonfinite_coordinate <- rep(FALSE, nrow(out))
  out_of_bounds <- rep(FALSE, nrow(out))
  outside_ontario_bounds <- rep(FALSE, nrow(out))
  invalid_coordinate <- rep(FALSE, nrow(out))
  if (length(coordinate_columns) == 2L) {
    raw_latitude <- as.character(out$latitude)
    raw_longitude <- as.character(out$longitude)
    missing_latitude <- is.na(raw_latitude) | !nzchar(trimws(raw_latitude))
    missing_longitude <- is.na(raw_longitude) | !nzchar(trimws(raw_longitude))
    incomplete_coordinate <- xor(missing_latitude, missing_longitude)
    out$latitude <- suppressWarnings(as.numeric(raw_latitude))
    out$longitude <- suppressWarnings(as.numeric(raw_longitude))
    supplied_coordinates <- !missing_latitude & !missing_longitude
    nonfinite_coordinate <- supplied_coordinates &
      (!is.finite(out$latitude) | !is.finite(out$longitude))
    bounded_coordinates <- supplied_coordinates & !nonfinite_coordinate
    out_of_bounds <- bounded_coordinates & (
      out$latitude < -90 | out$latitude > 90 |
        out$longitude < -180 | out$longitude > 180
    )
    globally_bounded_coordinates <- bounded_coordinates & !out_of_bounds
    outside_ontario_bounds <- globally_bounded_coordinates & (
      out$latitude < .ontario_bounds[["latitude_min"]] |
        out$latitude > .ontario_bounds[["latitude_max"]] |
        out$longitude < .ontario_bounds[["longitude_min"]] |
        out$longitude > .ontario_bounds[["longitude_max"]]
    )
    invalid_coordinate <- incomplete_coordinate |
      nonfinite_coordinate |
      out_of_bounds |
      outside_ontario_bounds
  }

  duplicate_evidence <- duplicated(out)
  invalid_row <- missing_postal |
    invalid_postal |
    invalid_coordinate |
    duplicate_evidence
  validation_reason <- rep("", nrow(out))
  reason_flags <- list(
    missing_postal_code = missing_postal,
    invalid_postal_code = invalid_postal,
    invalid_coordinate = invalid_coordinate,
    outside_ontario_bounds = outside_ontario_bounds,
    duplicate_evidence = duplicate_evidence
  )
  for (reason in names(reason_flags)) {
    index <- reason_flags[[reason]]
    validation_reason[index] <- ifelse(
      nzchar(validation_reason[index]),
      paste(validation_reason[index], reason, sep = ";"),
      reason
    )
  }

  report <- list(
    input_rows = nrow(out),
    accepted_rows = sum(!invalid_row),
    rejected_rows = sum(invalid_row),
    invalid_postal_rows = sum(invalid_postal),
    missing_postal_rows = sum(missing_postal),
    invalid_coordinate_rows = sum(invalid_coordinate),
    outside_ontario_bounds_rows = sum(outside_ontario_bounds),
    duplicate_evidence_rows = sum(duplicate_evidence)
  )
  if (on_invalid == "error" && any(invalid_row)) {
    if (any(missing_postal | invalid_postal | duplicate_evidence)) {
      error_message <- sprintf(
        "Invalid source data: %d of %d row(s) failed validation",
        report$rejected_rows,
        report$input_rows
      )
    } else if (any(incomplete_coordinate)) {
      error_message <- "latitude and longitude must be supplied together"
    } else if (any(nonfinite_coordinate)) {
      error_message <- "coordinates must be finite numeric values"
    } else if (any(out_of_bounds)) {
      error_message <- "coordinates are outside longitude/latitude bounds"
    } else {
      error_message <- "coordinates are outside broad Ontario bounds"
    }
    stop(
      error_message,
      call. = FALSE
    )
  }
  quarantine <- NULL
  if (on_invalid == "quarantine") {
    quarantine <- out[invalid_row, , drop = FALSE]
    quarantine$.opcc_validation_reason <- validation_reason[invalid_row]
  }
  out <- out[!invalid_row, , drop = FALSE]
  attr(out, "opcc_adapter") <- adapter
  attr(out, "opcc_validation") <- list(
    rows = nrow(out),
    unique_postal_codes = length(unique(out$postal_code))
  )
  attr(out, "opcc_validation_report") <- report
  if (!is.null(quarantine)) attr(out, "opcc_quarantine") <- quarantine
  out
}

#' Build a source-separated local evidence layer
#'
#' @param data A user-supplied postal-code evidence data frame.
#' @param adapter Source metadata created by [new_source_adapter()].
#' @param on_invalid How to handle invalid rows: error, drop them, or retain
#'   them in the `opcc_quarantine` attribute.
#' @return An `opcc_source_layer` data frame, never merged into a release.
#' @examples
#' adapter <- new_source_adapter(
#'   source_id = "example_open_addresses",
#'   licence = "Open Government Licence - Ontario",
#'   lineage = "Municipal open address points, retrieved from a city portal",
#'   retrieval_date = as.Date("2026-01-15"),
#'   schema_map = list(postal_code = "pc", latitude = "lat", longitude = "lon")
#' )
#' raw <- data.frame(
#'   pc = c("m5v3a8", "K1A 0A6", "not a postal code"),
#'   lat = c(43.6426, 45.4215, NA),
#'   lon = c(-79.3871, -75.6972, NA),
#'   stringsAsFactors = FALSE
#' )
#' layer <- build_source_layer(raw, adapter, on_invalid = "drop")
#' layer[c("postal_code", "source_id", "source_retrieval_date")]
#' class(layer)
#'
#' @export
build_source_layer <- function(
    data,
    adapter,
    on_invalid = c("error", "drop", "quarantine")) {
  .contribution_message()
  .check_adapter(adapter)
  out <- suppressMessages(validate_source_data(data, adapter, on_invalid))
  validation <- attr(out, "opcc_validation")
  validation_report <- attr(out, "opcc_validation_report")
  quarantine <- attr(out, "opcc_quarantine")
  out$source_id <- adapter$source_id
  out$source_licence <- adapter$licence
  out$source_lineage <- adapter$lineage
  out$source_retrieval_date <- as.character(adapter$retrieval_date)
  attr(out, "opcc_adapter") <- adapter
  attr(out, "opcc_validation") <- validation
  attr(out, "opcc_validation_report") <- validation_report
  if (!is.null(quarantine)) attr(out, "opcc_quarantine") <- quarantine
  attr(out, "opcc_source") <- "Local source-separated evidence; not a canonical OPCC release"
  class(out) <- c("opcc_source_layer", class(out))
  out
}

#' Profile a local source layer
#'
#' @param layer A layer created by [build_source_layer()].
#' @return A list of coverage and coordinate-quality metrics.
#' @examples
#' adapter <- new_source_adapter(
#'   source_id = "example_open_addresses",
#'   licence = "Open Government Licence - Ontario",
#'   lineage = "Municipal open address points, retrieved from a city portal",
#'   retrieval_date = as.Date("2026-01-15"),
#'   schema_map = list(postal_code = "pc", latitude = "lat", longitude = "lon")
#' )
#' raw <- data.frame(
#'   pc = c("M5V 3A8", "K1A 0A6"),
#'   lat = c(43.6426, 45.4215),
#'   lon = c(-79.3871, -75.6972),
#'   stringsAsFactors = FALSE
#' )
#' layer <- build_source_layer(raw, adapter)
#' profile_source_layer(layer)
#'
#' @export
profile_source_layer <- function(layer) {
  .contribution_message()
  if (!inherits(layer, "opcc_source_layer")) {
    stop("layer must be created by build_source_layer()", call. = FALSE)
  }
  has_coordinates <- all(c("latitude", "longitude") %in% names(layer))
  list(
    source_id = unique(layer$source_id),
    rows = nrow(layer),
    postal_codes = length(unique(layer$postal_code)),
    duplicate_postal_codes = sum(duplicated(layer$postal_code)),
    coordinate_rows = if (has_coordinates) sum(stats::complete.cases(layer[c("latitude", "longitude")])) else 0L,
    missing_coordinate_rows = if (has_coordinates) sum(!stats::complete.cases(layer[c("latitude", "longitude")])) else nrow(layer)
  )
}

#' Create a reviewable local-source contribution bundle
#'
#' @param layer A layer created by [build_source_layer()].
#' @param output_dir Explicit directory in which to create a new bundle directory.
#' @param fixture_rows Maximum normalized sample rows to include.
#' @return A named list of generated bundle paths.
#' @examples
#' adapter <- new_source_adapter(
#'   source_id = "example_open_addresses",
#'   licence = "Open Government Licence - Ontario",
#'   lineage = "Municipal open address points, retrieved from a city portal",
#'   retrieval_date = as.Date("2026-01-15")
#' )
#' layer <- build_source_layer(
#'   data.frame(postal_code = c("M5V 3A8", "K1A 0A6")),
#'   adapter
#' )
#'
#' # `output_dir` is required and must be explicit; a session temporary
#' # directory keeps the example self-contained.
#' output_dir <- tempfile("opcc-bundle")
#' bundle <- contribution_bundle(layer, output_dir = output_dir)
#' basename(unlist(bundle))
#'
#' unlink(output_dir, recursive = TRUE)
#'
#' @export
contribution_bundle <- function(layer, output_dir = NULL, fixture_rows = 100L) {
  .contribution_message()
  if (!inherits(layer, "opcc_source_layer")) {
    stop("layer must be created by build_source_layer()", call. = FALSE)
  }
  adapter <- attr(layer, "opcc_adapter")
  .check_adapter(adapter)
  if (is.null(output_dir) || !is.character(output_dir) || length(output_dir) != 1L ||
      is.na(output_dir) || !nzchar(output_dir)) {
    stop("output_dir must be an explicit non-empty directory path", call. = FALSE)
  }
  fixture_rows <- as.integer(fixture_rows)
  if (is.na(fixture_rows) || fixture_rows < 1L) stop("fixture_rows must be at least one", call. = FALSE)
  bundle_dir <- file.path(output_dir, paste0("opcc-", adapter$source_id, "-contribution"))
  if (dir.exists(bundle_dir) || file.exists(bundle_dir)) {
    stop("Contribution bundle path already exists", call. = FALSE)
  }
  dir.create(bundle_dir, recursive = TRUE)
  fixture <- layer[order(layer$postal_code), , drop = FALSE]
  fixture <- utils::head(fixture, fixture_rows)
  fixture_path <- file.path(bundle_dir, "fixture.csv")
  adapter_path <- file.path(bundle_dir, "adapter.json")
  profile_path <- file.path(bundle_dir, "quality-report.json")
  provenance_path <- file.path(bundle_dir, "provenance.json")
  utils::write.csv(fixture, fixture_path, row.names = FALSE, na = "")
  jsonlite::write_json(.json_safe(adapter), adapter_path, auto_unbox = TRUE, pretty = TRUE)
  jsonlite::write_json(suppressMessages(profile_source_layer(layer)), profile_path, auto_unbox = TRUE, pretty = TRUE)
  jsonlite::write_json(
    list(
      source_id = adapter$source_id,
      licence = adapter$licence,
      lineage = adapter$lineage,
      retrieval_date = as.character(adapter$retrieval_date),
      endpoint = adapter$endpoint,
      schema_map = adapter$schema_map,
      checksum = adapter$checksum,
      location_type = adapter$location_type,
      coordinate_method = adapter$coordinate_method,
      authority_level = adapter$authority_level,
      coverage_type = adapter$coverage_type,
      update_frequency = adapter$update_frequency,
      local_only = TRUE,
      canonical_release_modified = FALSE
    ),
    provenance_path,
    auto_unbox = TRUE,
    pretty = TRUE
  )
  structure(
    list(
      directory = bundle_dir,
      fixture = fixture_path,
      adapter = adapter_path,
      quality_report = profile_path,
      provenance = provenance_path
    ),
    class = "opcc_contribution_bundle"
  )
}

#' Create a GitHub source-proposal issue URL for a contribution bundle
#'
#' The returned URL opens GitHub's issue composer with bundle provenance
#' prefilled. GitHub does not support file attachments through this URL, so the
#' contributor must attach the generated bundle manually before submitting.
#'
#' @param bundle A bundle returned by [contribution_bundle()].
#' @param repository GitHub repository in `owner/repository` form.
#' @return A GitHub issue-composer URL.
#' @examples
#' adapter <- new_source_adapter(
#'   source_id = "example_open_addresses",
#'   licence = "Open Government Licence - Ontario",
#'   lineage = "Municipal open address points, retrieved from a city portal",
#'   retrieval_date = as.Date("2026-01-15")
#' )
#' layer <- build_source_layer(
#'   data.frame(postal_code = c("M5V 3A8", "K1A 0A6")),
#'   adapter
#' )
#' output_dir <- tempfile("opcc-bundle")
#' bundle <- contribution_bundle(layer, output_dir = output_dir)
#'
#' issue_url <- contribution_issue_url(bundle)
#' substr(issue_url, 1, 55)
#'
#' unlink(output_dir, recursive = TRUE)
#'
#' @export
contribution_issue_url <- function(bundle, repository = "lennon-li/OPCC") {
  if (!inherits(bundle, "opcc_contribution_bundle") || !file.exists(bundle$provenance)) {
    stop("bundle must be an existing contribution_bundle() result", call. = FALSE)
  }
  if (!is.character(repository) || length(repository) != 1L ||
      !grepl("^[^/[:space:]]+/[^/[:space:]]+$", repository)) {
    stop("repository must use owner/repository form", call. = FALSE)
  }
  provenance <- jsonlite::read_json(bundle$provenance, simplifyVector = TRUE)
  endpoint <- if (is.null(provenance$endpoint) || !is.character(provenance$endpoint) ||
      length(provenance$endpoint) != 1L || !isTRUE(nzchar(provenance$endpoint))) {
    "not supplied"
  } else {
    provenance$endpoint
  }
  body <- paste(
    "## Source",
    paste0("- Source name and stable identifier: ", provenance$source_id),
    paste0("- Public endpoint: ", endpoint),
    paste0("- Licence or permission statement: ", provenance$licence),
    paste0("- Retrieval or creation date: ", provenance$retrieval_date),
    paste0("- Source lineage and collection method: ", provenance$lineage),
    "",
    "## Contribution bundle",
    "Attach the generated fixture, adapter configuration, quality report, and provenance files from this bundle before submitting.",
    sep = "\n"
  )
  query <- paste0(
    "template=source-proposal.md&title=Source%3A%20",
    utils::URLencode(provenance$source_id, reserved = TRUE),
    "&body=", utils::URLencode(body, reserved = TRUE)
  )
  paste0("https://github.com/", repository, "/issues/new?", query)
}

#' Open a GitHub source-proposal issue for a contribution bundle
#'
#' @inheritParams contribution_issue_url
#' @param open Whether to open the returned URL in a browser. Defaults to
#'   `FALSE` so submission remains an explicit user action.
#' @return Invisibly, the GitHub issue-composer URL.
#' @examples
#' adapter <- new_source_adapter(
#'   source_id = "example_open_addresses",
#'   licence = "Open Government Licence - Ontario",
#'   lineage = "Municipal open address points, retrieved from a city portal",
#'   retrieval_date = as.Date("2026-01-15")
#' )
#' layer <- build_source_layer(
#'   data.frame(postal_code = c("M5V 3A8", "K1A 0A6")),
#'   adapter
#' )
#' output_dir <- tempfile("opcc-bundle")
#' bundle <- contribution_bundle(layer, output_dir = output_dir)
#'
#' # open = FALSE keeps submission an explicit user action, so nothing is
#' # sent and no browser is opened here.
#' issue_url <- suppressMessages(open_contribution_issue(bundle))
#' substr(issue_url, 1, 55)
#'
#' unlink(output_dir, recursive = TRUE)
#'
#' @export
open_contribution_issue <- function(bundle, repository = "lennon-li/OPCC", open = FALSE) {
  url <- contribution_issue_url(bundle, repository)
  if (isTRUE(open)) {
    if (!interactive()) stop("open = TRUE requires an interactive R session", call. = FALSE)
    utils::browseURL(url)
  }
  message("Attach the generated contribution bundle files, then submit the GitHub issue: ", url)
  invisible(url)
}
