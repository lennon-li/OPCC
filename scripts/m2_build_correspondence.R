# OPCC M2 correspondence build.
# NAR-only observed postal associations joined to 2021 DBUID geography.

normalize_pc <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- gsub("[[:space:]]+", "", x)
  ok <- !is.na(x) & grepl("^[A-Z][0-9][A-Z][0-9][A-Z][0-9]$", x)
  out <- rep(NA_character_, length(x))
  out[ok] <- paste0(substr(x[ok], 1, 3), " ", substr(x[ok], 4, 6))
  out
}

first_column <- function(data, candidates, label, required = TRUE) {
  hit <- candidates[candidates %in% names(data)]
  if (length(hit) > 0) return(hit[[1]])
  if (required) {
    stop("Missing ", label, " column; tried: ", paste(candidates, collapse = ", "))
  }
  NA_character_
}

aggregate_m2_evidence <- function(data, geography_columns = character()) {
  required <- c("postal_code", "LOC_GUID", "DBUID")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop("Missing required aggregation columns: ", paste(missing, collapse = ", "))
  }

  valid <- data[
    !is.na(data$postal_code) & data$postal_code != "" &
      !is.na(data$LOC_GUID) & data$LOC_GUID != "" &
      !is.na(data$DBUID) & data$DBUID != "", , drop = FALSE
  ]
  if (nrow(valid) == 0) stop("No valid NAR observations remain after filtering")

  key <- paste(valid$postal_code, valid$DBUID, sep = "\r")
  groups <- split(seq_len(nrow(valid)), key, drop = TRUE)
  rows <- lapply(groups, function(index) {
    first <- valid[index[1], , drop = FALSE]
    result <- data.frame(
      postal_code = as.character(first$postal_code),
      DBUID = as.character(first$DBUID),
      n_observations = length(index),
      n_unique_addresses = length(unique(valid$LOC_GUID[index])),
      n_sources = 1L,
      stringsAsFactors = FALSE
    )
    for (column in geography_columns) {
      result[[column]] <- as.character(first[[column]])
    }
    result
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL

  order_index <- order(result$postal_code, -result$n_unique_addresses, result$DBUID)
  result <- result[order_index, , drop = FALSE]
  result$address_weight <- ave(
    result$n_unique_addresses,
    result$postal_code,
    FUN = function(x) x / sum(x)
  )
  result$confidence <- result$address_weight
  result$best_link <- as.logical(ave(
    seq_len(nrow(result)), result$postal_code,
    FUN = function(x) seq_along(x) == 1L
  ))

  sums <- tapply(result$address_weight, result$postal_code, sum)
  if (any(!is.finite(result$address_weight) | result$address_weight < 0)) {
    stop("M2 weights must be finite and non-negative")
  }
  if (any(abs(sums - 1) > 1e-8)) stop("M2 weights do not sum to 1 per postal code")
  best_counts <- table(result$postal_code[result$best_link])
  if (any(best_counts != 1L)) {
    stop("M2 must have exactly one best link per postal code")
  }
  if (any(duplicated(result[c("postal_code", "DBUID")]))) {
    stop("M2 contains duplicate postal_code/DBUID keys")
  }
  result
}

sha256_file <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  digest::digest(path, algo = "sha256", file = TRUE)
}

build_m2_correspondence <- function() {
  if (!requireNamespace("sf", quietly = TRUE) ||
      !requireNamespace("dplyr", quietly = TRUE) ||
      !requireNamespace("readr", quietly = TRUE) ||
      !requireNamespace("jsonlite", quietly = TRUE) ||
      !requireNamespace("digest", quietly = TRUE)) {
    stop("M2 requires sf, dplyr, readr, jsonlite, and digest")
  }

  root <- getwd()
  nar_dir <- file.path(root, ".scratch", "m1_nar")
  db_path <- file.path(root, ".scratch", "shp", "ldb_000b21a_e.shp")
  gaf_path <- file.path(root, ".scratch", "gaf", "2021_92-151_X.csv")
  out_dir <- file.path(root, ".scratch", "m2")
  if (!dir.exists(nar_dir)) stop("Missing NAR scratch directory: ", nar_dir)
  if (!file.exists(db_path)) stop("Missing DB shapefile: ", db_path)
  if (!file.exists(gaf_path)) stop("Missing GAF file: ", gaf_path)

  address_files <- sort(list.files(
    file.path(nar_dir, "Addresses"), "^Address_35_.*[.]csv$", full.names = TRUE
  ))
  location_files <- sort(list.files(
    file.path(nar_dir, "Locations"), "^Location_35_.*[.]csv$", full.names = TRUE
  ))
  if (length(address_files) == 0) stop("No Ontario NAR address files found")
  if (length(location_files) == 0) stop("No Ontario NAR location files found")

  read_all <- function(paths) {
    dplyr::bind_rows(lapply(paths, function(path) {
      readr::read_csv(path, col_types = readr::cols(.default = "c"),
                      show_col_types = FALSE, name_repair = "minimal")
    }))
  }
  addresses <- read_all(address_files)
  locations <- read_all(location_files)
  names(addresses) <- sub("^\\ufeff", "", names(addresses))
  names(locations) <- sub("^\\ufeff", "", names(locations))
  address_loc <- first_column(addresses, c("LOC_GUID"), "NAR address key")
  location_loc <- first_column(locations, c("LOC_GUID"), "NAR location key")
  postal_col <- first_column(addresses, c("MAIL_POSTAL_CODE"), "NAR postal")
  lat_rep <- first_column(locations, c("BF_REPPOINT_LATITUDE"), "preferred latitude")
  lon_rep <- first_column(locations, c("BF_REPPOINT_LONGITUDE"), "preferred longitude")
  lat_bg <- first_column(locations, c("BG_LATITUDE"), "fallback latitude")
  lon_bg <- first_column(locations, c("BG_LONGITUDE"), "fallback longitude")

  locations$latitude <- suppressWarnings(as.numeric(locations[[lat_rep]]))
  locations$longitude <- suppressWarnings(as.numeric(locations[[lon_rep]]))
  fallback_lat <- is.na(locations$latitude)
  fallback_lon <- is.na(locations$longitude)
  locations$latitude[fallback_lat] <- suppressWarnings(as.numeric(locations[[lat_bg]][fallback_lat]))
  locations$longitude[fallback_lon] <- suppressWarnings(as.numeric(locations[[lon_bg]][fallback_lon]))
  locations <- locations[, c(location_loc, "latitude", "longitude"), drop = FALSE]
  names(locations)[1] <- "LOC_GUID"
  addresses$postal_code <- normalize_pc(addresses[[postal_col]])
  addresses$LOC_GUID <- as.character(addresses[[address_loc]])
  address_located <- dplyr::left_join(
    addresses[, c("LOC_GUID", "postal_code")], locations, by = "LOC_GUID"
  )
  address_located$latitude <- as.numeric(address_located$latitude)
  address_located$longitude <- as.numeric(address_located$longitude)
  address_located <- address_located[
    !is.na(address_located$latitude) & !is.na(address_located$longitude), , drop = FALSE
  ]
  if (nrow(address_located) == 0) stop("No NAR observations have usable coordinates")

  points <- sf::st_as_sf(
    address_located, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE
  )
  db <- sf::st_read(db_path, quiet = TRUE)
  if (!"PRUID" %in% names(db) || !"DBUID" %in% names(db)) {
    stop("DB shapefile must contain PRUID and DBUID")
  }
  db <- db[as.character(db$PRUID) == "35", c("DBUID", "geometry")]
  points <- sf::st_transform(points, sf::st_crs(db))
  joined <- sf::st_join(points, db, join = sf::st_intersects, left = FALSE)
  joined <- sf::st_drop_geometry(joined)
  joined$DBUID <- as.character(joined$DBUID)
  if (nrow(joined) == 0) stop("No coordinate observations intersect Ontario DB polygons")
  point_matches <- dplyr::summarise(
    dplyr::group_by(joined, LOC_GUID),
    n_dbuid = dplyr::n_distinct(DBUID), .groups = "drop"
  )
  if (any(point_matches$n_dbuid > 1L)) {
    stop("Some LOC_GUID points intersect multiple DBUID polygons; inspect boundary matches")
  }

  gaf <- readr::read_csv(gaf_path, col_types = readr::cols(.default = "c"),
                         show_col_types = FALSE, name_repair = "minimal")
  gaf_db <- first_column(gaf, c("DBUID_IDIDU", "DBUID"), "GAF DBUID")
  geography_specs <- list(
    DAUID = c("DAUID", "DAUID_ADIDU"),
    CTUID = c("CTUID", "CTUID_SRIDU"),
    CSDUID = c("CSDUID", "CSDUID_IDI"),
    CCSUID = c("CCSUID", "CCSUID_SRIDU"),
    CDUID = c("CDUID", "CDUID_ID"),
    CMASUID = c("CMASUID", "CMASUID_ID"),
    FEDUID = c("FEDUID", "FEDUID_ID")
  )
  geography_columns <- names(geography_specs)[vapply(
    geography_specs, function(candidates) any(candidates %in% names(gaf)), logical(1)
  )]
  if (!"DAUID" %in% geography_columns) stop("GAF must contain DAUID")
  gaf_map <- data.frame(DBUID = as.character(gaf[[gaf_db]]), stringsAsFactors = FALSE)
  for (column in geography_columns) {
    source_column <- first_column(gaf, geography_specs[[column]], column)
    gaf_map[[column]] <- as.character(gaf[[source_column]])
  }
  gaf_map$DBUID <- as.character(gaf_map$DBUID)
  if (anyDuplicated(gaf_map$DBUID)) stop("GAF has duplicate DBUID rows")
  joined <- dplyr::left_join(joined, gaf_map, by = "DBUID")
  if (anyNA(joined$DAUID)) stop("Some DBUID observations have no GAF DAUID")

  result <- aggregate_m2_evidence(joined, geography_columns)
  result$source_vintage <- "2026-06-26"
  result$census_vintage <- "2021"
  result <- result[, c(
    "postal_code", "DBUID", geography_columns, "n_observations",
    "n_unique_addresses", "n_sources", "address_weight", "best_link",
    "confidence", "source_vintage", "census_vintage"
  ), drop = FALSE]

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- file.path(out_dir, "m2_correspondence.csv")
  manifest_path <- file.path(out_dir, "m2_manifest.json")
  readr::write_csv(result, csv_path)
  code_version <- tryCatch(
    system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)[1],
    error = function(e) NA_character_
  )
  source_files <- c(address_files, location_files, db_path, gaf_path, csv_path)
  manifest <- list(
    source_urls = list(nar_catalogue = "https://www150.statcan.gc.ca/n1/en/catalogue/46260002",
                       census_gaf = "https://www12.statcan.gc.ca/census-recensement/2021/geo/aip-pia/attribute-attribs/files-fichiers/2021_92-151_X.zip"),
    source_paths = source_files,
    sha256 = setNames(lapply(source_files, sha256_file), source_files),
    source_vintage = "2026-06-26", census_vintage = "2021",
    code_version = code_version,
    build_timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    row_counts = list(correspondence_rows = nrow(result), input_observations = nrow(joined)),
    validation_results = list(weights_sum_to_one = TRUE, unique_best_link = TRUE,
                              unique_postal_dbuid = TRUE, restricted_sources_used = FALSE)
  )
  jsonlite::write_json(manifest, manifest_path, pretty = TRUE, auto_unbox = TRUE)
  invisible(result)
}

if (sys.nframe() == 0) build_m2_correspondence()
