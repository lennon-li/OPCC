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

.coerce_da_correspondence <- function(x, vintage) {
  numeric_columns <- intersect(c("allocation_weight"), names(x))
  integer_columns <- intersect(c("n_contributing_dbs"), names(x))
  for (column in numeric_columns) x[[column]] <- as.numeric(x[[column]])
  for (column in integer_columns) x[[column]] <- as.integer(x[[column]])
  if ("best_link" %in% names(x)) x$best_link <- x$best_link == "TRUE"
  attr(x, "opcc_vintage") <- vintage
  attr(x, "opcc_source") <- "OPCC direct postal-code-to-DA correspondence"
  x
}

.collapse_values <- function(x) paste(sort(unique(as.character(x))), collapse = "|")

#' Aggregate postal-code-to-DB evidence to DA links
#'
#' @param correspondence A postal-code-to-DB correspondence data frame.
#' @return A data frame with one row per `postal_code` and `DAUID`.
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
#' @export
list_vintages <- function(level = c("DB", "DA")) {
  level <- match.arg(level)
  names(if (level == "DB") .index() else .da_index())
}

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

#' Download, cache, and verify a direct DA correspondence release
#'
#' @param vintage A value returned by [list_vintages()] for `level = "DA"`.
#' @param cache_dir Directory used for verified downloaded files.
#' @param offline Require an already cached verified file.
#' @return A data frame of postal-code-to-DA links with contributing DB lineage.
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
  if (level == "DA" && !is.null(correspondence)) x <- aggregate_da_correspondence(x)
  out <- x[x$postal_code %in% pcs, , drop = FALSE]
  if (!all_links) out <- out[out$best_link, , drop = FALSE]
  attr(out, "unmatched") <- setdiff(pcs, unique(out$postal_code))
  out
}

#' Read and verify a release manifest
#'
#' @param vintage A value returned by [list_vintages()].
#' @param level Geography level, `"DB"` or `"DA"`.
#' @param cache_dir Directory used for verified downloaded files.
#' @param offline Require an already cached verified file.
#' @return A parsed JSON list.
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
#' @param cache_dir Directory used for verified downloaded files.
#' @param offline Require an already cached verified file.
#' @return Invisibly `TRUE`, or an error describing a failed invariant.
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
#' @return An `opcc_source_adapter` object.
#' @export
new_source_adapter <- function(
    source_id,
    licence,
    lineage,
    retrieval_date = Sys.Date(),
    schema_map = list(postal_code = "postal_code"),
    endpoint = NULL,
    checksum = NULL) {
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
  if (!is.list(schema_map) || is.null(names(schema_map)) || !"postal_code" %in% names(schema_map)) {
    stop("schema_map must be a named list containing postal_code", call. = FALSE)
  }
  if (!is.null(checksum) && (!is.character(checksum) || length(checksum) != 1L ||
      !grepl("^[0-9a-fA-F]{64}$", checksum))) {
    stop("checksum must be a 64-character SHA-256 hex string", call. = FALSE)
  }
  retrieval_date <- as.Date(retrieval_date)
  if (is.na(retrieval_date)) stop("retrieval_date must be a valid date", call. = FALSE)
  structure(
    list(
      source_id = source_id,
      licence = licence,
      lineage = lineage,
      retrieval_date = retrieval_date,
      schema_map = schema_map,
      endpoint = endpoint,
      checksum = checksum
    ),
    class = "opcc_source_adapter"
  )
}

#' Load the versioned GeoNames supplementary-point adapter
#'
#' @return An `opcc_source_adapter` for the packaged GeoNames point artifact.
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
    checksum = spec$artifact_sha256
  )
}

#' Validate local postal-code evidence
#'
#' @param data A data frame with a postal-code field named by `adapter`.
#' @param adapter Source metadata created by [new_source_adapter()].
#' @return A normalized data frame with `postal_code` and validation metadata.
#' @export
validate_source_data <- function(data, adapter) {
  .contribution_message()
  .check_adapter(adapter)
  if (!is.data.frame(data)) stop("data must be a data frame", call. = FALSE)
  source_column <- adapter$schema_map$postal_code
  if (length(source_column) != 1L || !source_column %in% names(data)) {
    stop("data is missing the adapter postal_code field", call. = FALSE)
  }
  out <- data
  out$postal_code <- normalize_postal_code(as.character(data[[source_column]]), strict = TRUE)
  if (anyDuplicated(out)) stop("data contains duplicate evidence rows", call. = FALSE)
  coordinate_columns <- intersect(c("latitude", "longitude"), names(out))
  if (length(coordinate_columns) == 1L) {
    stop("latitude and longitude must be supplied together", call. = FALSE)
  }
  if (length(coordinate_columns) == 2L) {
    out$latitude <- suppressWarnings(as.numeric(out$latitude))
    out$longitude <- suppressWarnings(as.numeric(out$longitude))
    if (any(!is.finite(out$latitude) | !is.finite(out$longitude))) {
      stop("coordinates must be finite numeric values", call. = FALSE)
    }
    if (any(out$latitude < -90 | out$latitude > 90 | out$longitude < -180 | out$longitude > 180)) {
      stop("coordinates are outside longitude/latitude bounds", call. = FALSE)
    }
  }
  attr(out, "opcc_adapter") <- adapter
  attr(out, "opcc_validation") <- list(rows = nrow(out), unique_postal_codes = length(unique(out$postal_code)))
  out
}

#' Build a source-separated local evidence layer
#'
#' @param data A user-supplied postal-code evidence data frame.
#' @param adapter Source metadata created by [new_source_adapter()].
#' @return An `opcc_source_layer` data frame, never merged into a release.
#' @export
build_source_layer <- function(data, adapter) {
  .contribution_message()
  .check_adapter(adapter)
  out <- suppressMessages(validate_source_data(data, adapter))
  out$source_id <- adapter$source_id
  out$source_licence <- adapter$licence
  out$source_lineage <- adapter$lineage
  out$source_retrieval_date <- as.character(adapter$retrieval_date)
  attr(out, "opcc_adapter") <- adapter
  attr(out, "opcc_source") <- "Local source-separated evidence; not a canonical OPCC release"
  class(out) <- c("opcc_source_layer", class(out))
  out
}

#' Profile a local source layer
#'
#' @param layer A layer created by [build_source_layer()].
#' @return A list of coverage and coordinate-quality metrics.
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
#' @param output_dir Directory in which to create a new bundle directory.
#' @param fixture_rows Maximum normalized sample rows to include.
#' @return A named list of generated bundle paths.
#' @export
contribution_bundle <- function(layer, output_dir = getwd(), fixture_rows = 100L) {
  .contribution_message()
  if (!inherits(layer, "opcc_source_layer")) {
    stop("layer must be created by build_source_layer()", call. = FALSE)
  }
  adapter <- attr(layer, "opcc_adapter")
  .check_adapter(adapter)
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
