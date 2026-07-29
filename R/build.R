.check_build_deps <- function(need_sf = FALSE) {
  pkgs <- c("dplyr", "readr", "digest", "jsonlite")
  if (need_sf) pkgs <- c(pkgs, "sf")
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0L) {
    stop(
      "Build requires: ", paste(missing, collapse = ", "),
      "\nInstall with: install.packages(c(",
      paste0('"', missing, '"', collapse = ", "), "))",
      call. = FALSE
    )
  }
}

.first_column <- function(data, candidates, label, required = TRUE) {
  hit <- candidates[candidates %in% names(data)]
  if (length(hit) > 0L) return(hit[[1L]])
  if (required) {
    stop("Missing ", label, " column; tried: ",
         paste(candidates, collapse = ", "), call. = FALSE)
  }
  NA_character_
}

.assign_ontario_points <- function(points, province_boundaries, db_boundaries) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("Point assignment requires the sf package", call. = FALSE)
  }
  if (!is.data.frame(points) ||
      !all(c("latitude", "longitude") %in% names(points))) {
    stop("points must be a data frame containing latitude and longitude",
         call. = FALSE)
  }
  latitude <- suppressWarnings(as.numeric(points$latitude))
  longitude <- suppressWarnings(as.numeric(points$longitude))
  if (any(!is.finite(latitude) | !is.finite(longitude))) {
    stop("Points must have finite coordinates", call. = FALSE)
  }
  if (!inherits(province_boundaries, "sf") ||
      !"PRUID" %in% names(province_boundaries)) {
    stop("province_boundaries must be an sf object containing PRUID",
         call. = FALSE)
  }
  if (!inherits(db_boundaries, "sf") ||
      !all(c("PRUID", "DBUID") %in% names(db_boundaries))) {
    stop("db_boundaries must be an sf object containing PRUID and DBUID",
         call. = FALSE)
  }

  ontario_boundary <- province_boundaries[
    as.character(province_boundaries$PRUID) == "35", , drop = FALSE
  ]
  ontario_db <- db_boundaries[
    as.character(db_boundaries$PRUID) == "35", "DBUID", drop = FALSE
  ]
  if (nrow(ontario_boundary) == 0L) {
    stop("province_boundaries has no Ontario PRUID 35 geometry", call. = FALSE)
  }
  if (nrow(ontario_db) == 0L) {
    stop("db_boundaries has no Ontario PRUID 35 geometry", call. = FALSE)
  }

  point_sf <- sf::st_as_sf(
    transform(points, latitude = latitude, longitude = longitude),
    coords = c("longitude", "latitude"), crs = 4326, remove = FALSE
  )
  province_crs <- if (sf::st_is_longlat(ontario_boundary)) {
    sf::st_crs(3347)
  } else {
    sf::st_crs(ontario_boundary)
  }
  province_points <- sf::st_transform(point_sf, province_crs)
  province_geometry <- sf::st_union(sf::st_geometry(
    sf::st_transform(ontario_boundary, province_crs)
  ))
  inside_ontario <- lengths(sf::st_intersects(
    province_points, province_geometry
  )) > 0L
  if (any(!inside_ontario)) {
    stop(sprintf("%d point(s) fall outside the Ontario boundary",
                 sum(!inside_ontario)), call. = FALSE)
  }

  db_crs <- if (sf::st_is_longlat(ontario_db)) {
    sf::st_crs(3347)
  } else {
    sf::st_crs(ontario_db)
  }
  ontario_db <- sf::st_transform(ontario_db, db_crs)
  db_points <- sf::st_transform(point_sf, db_crs)
  db_matches <- sf::st_intersects(db_points, ontario_db)
  match_counts <- lengths(db_matches)
  if (any(match_counts > 1L)) {
    stop(sprintf("%d point(s) intersect multiple 2021 Ontario DBs",
                 sum(match_counts > 1L)), call. = FALSE)
  }

  matched <- match_counts == 1L
  dbuid <- rep(NA_character_, nrow(points))
  dbuid[matched] <- as.character(ontario_db$DBUID[
    vapply(db_matches[matched], `[[`, integer(1), 1L)
  ])
  out <- points
  out$latitude <- latitude
  out$longitude <- longitude
  out$DBUID <- dbuid
  out$db_match_status <- ifelse(
    matched, "matched_2021_ontario_db", "unmatched_no_2021_ontario_db"
  )
  attr(out, "opcc_spatial_validation") <- list(
    input_points = nrow(points),
    matched_points = sum(matched),
    unmatched_points = sum(!matched)
  )
  out
}

.validate_point_geography <- function(points, dauid_column = "DAUID_ADIDU") {
  required <- c("DBUID", dauid_column, "db_match_status")
  if (!is.data.frame(points) || !all(required %in% names(points))) {
    stop("points must contain DBUID, db_match_status, and ", dauid_column,
         call. = FALSE)
  }
  matched <- points$db_match_status == "matched_2021_ontario_db"
  has_db <- !is.na(points$DBUID) & nzchar(trimws(as.character(points$DBUID)))
  has_da <- !is.na(points[[dauid_column]]) &
    nzchar(trimws(as.character(points[[dauid_column]])))
  if (any(matched != (has_db & has_da))) {
    stop("db_match_status is inconsistent with DBUID/DAUID nullability",
         call. = FALSE)
  }
  list(
    input_points = nrow(points),
    matched_points = sum(matched),
    unmatched_points = sum(!matched)
  )
}

.read_nar_csv <- function(path, col_select) {
  raw <- readr::read_csv(
    path,
    col_select = dplyr::any_of(col_select),
    col_types = readr::cols(.default = "c"),
    show_col_types = FALSE,
    name_repair = "minimal"
  )
  names(raw) <- gsub("^\xef\xbb\xbf", "", names(raw))
  names(raw) <- trimws(names(raw))
  raw
}

#' Build Ontario postal code centroids from NAR and GeoNames
#'
#' Reads the extracted NAR Address and Location part files, computes the
#' mean coordinate per postal code, and merges with GeoNames Ontario
#' centroids. NAR centroids take priority; GeoNames fills gaps.
#'
#' @param nar_dir Path returned by [download_nar()].
#' @param geonames_txt Path returned by [download_geonames()].
#' @param output_dir Directory for output files. Defaults to
#'   `postal_centroids` inside the build cache.
#' @return Invisibly, the path to `ontario_postal_centroids.csv`.
#' @export
build_centroids <- function(nar_dir, geonames_txt, output_dir = NULL) {
  .check_build_deps(need_sf = FALSE)
  if (is.null(output_dir)) {
    output_dir <- file.path(.opcc_build_cache(NULL), "postal_centroids")
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  out_csv <- file.path(output_dir, "ontario_postal_centroids.csv")

  message("[centroids] Step 1/5: Reading NAR Location files")
  loc_parts <- sort(list.files(
    file.path(nar_dir, "Locations"), "^Location_35_.*[.]csv$",
    full.names = TRUE
  ))
  if (length(loc_parts) == 0L) {
    stop("No Ontario NAR Location files in ", nar_dir, call. = FALSE)
  }
  loc_cols <- c("LOC_GUID", "BF_REPPOINT_LATITUDE", "BF_REPPOINT_LONGITUDE",
                "BG_LATITUDE", "BG_LONGITUDE")
  loc_all <- dplyr::bind_rows(lapply(loc_parts, function(p) {
    message("  reading ", basename(p))
    .read_nar_csv(p, loc_cols)
  }))
  message(sprintf("  %s location rows", format(nrow(loc_all), big.mark = ",")))

  loc_all$bf_lat <- suppressWarnings(as.numeric(loc_all$BF_REPPOINT_LATITUDE))
  loc_all$bf_lon <- suppressWarnings(as.numeric(loc_all$BF_REPPOINT_LONGITUDE))
  loc_all$bg_lat <- suppressWarnings(as.numeric(loc_all$BG_LATITUDE))
  loc_all$bg_lon <- suppressWarnings(as.numeric(loc_all$BG_LONGITUDE))
  loc_all$best_lat <- ifelse(is.na(loc_all$bf_lat), loc_all$bg_lat, loc_all$bf_lat)
  loc_all$best_lon <- ifelse(is.na(loc_all$bf_lon), loc_all$bg_lon, loc_all$bf_lon)
  loc_all <- loc_all[, c("LOC_GUID", "best_lat", "best_lon")]

  message("[centroids] Step 2/5: Reading NAR Address files and joining")
  addr_parts <- sort(list.files(
    file.path(nar_dir, "Addresses"), "^Address_35_.*[.]csv$",
    full.names = TRUE
  ))
  if (length(addr_parts) == 0L) {
    stop("No Ontario NAR Address files in ", nar_dir, call. = FALSE)
  }
  pc_accum <- NULL
  for (ap in addr_parts) {
    message("  reading ", basename(ap))
    addr_chunk <- .read_nar_csv(ap, c("LOC_GUID", "MAIL_POSTAL_CODE"))
    addr_chunk$pc_norm <- normalize_postal_code(addr_chunk$MAIL_POSTAL_CODE)
    chunk_joined <- dplyr::left_join(
      addr_chunk[, c("LOC_GUID", "pc_norm")], loc_all, by = "LOC_GUID"
    )
    chunk_agg <- chunk_joined |>
      dplyr::filter(!is.na(pc_norm)) |>
      dplyr::group_by(pc_norm) |>
      dplyr::summarise(
        addr_count = dplyr::n(),
        addr_with_coords = sum(!is.na(best_lat)),
        sum_lat = sum(best_lat, na.rm = TRUE),
        sum_lon = sum(best_lon, na.rm = TRUE),
        .groups = "drop"
      )
    if (is.null(pc_accum)) {
      pc_accum <- chunk_agg
    } else {
      pc_accum <- dplyr::bind_rows(pc_accum, chunk_agg) |>
        dplyr::group_by(pc_norm) |>
        dplyr::summarise(
          addr_count = sum(addr_count),
          addr_with_coords = sum(addr_with_coords),
          sum_lat = sum(sum_lat),
          sum_lon = sum(sum_lon),
          .groups = "drop"
        )
    }
  }
  nar_centroids <- pc_accum |>
    dplyr::mutate(
      nar_lat = ifelse(addr_with_coords > 0, sum_lat / addr_with_coords, NA_real_),
      nar_lon = ifelse(addr_with_coords > 0, sum_lon / addr_with_coords, NA_real_)
    ) |>
    dplyr::select(pc_norm, nar_lat, nar_lon, addr_count, addr_with_coords)
  message(sprintf("  %s NAR postal codes, %s with coordinates",
                  format(nrow(nar_centroids), big.mark = ","),
                  format(sum(!is.na(nar_centroids$nar_lat)), big.mark = ",")))

  message("[centroids] Step 3/5: Reading GeoNames Ontario")
  gn_cols <- c("country_code", "postal_code", "place_name",
               "admin_name1", "admin_code1", "admin_name2", "admin_code2",
               "admin_name3", "admin_code3", "latitude", "longitude",
               "accuracy")
  gn_raw <- readr::read_tsv(
    geonames_txt, col_names = gn_cols,
    col_types = readr::cols(.default = "c"), show_col_types = FALSE
  )
  gn_on <- gn_raw |>
    dplyr::filter(admin_code1 == "ON") |>
    dplyr::mutate(
      pc_norm = normalize_postal_code(postal_code),
      gn_lat = suppressWarnings(as.numeric(latitude)),
      gn_lon = suppressWarnings(as.numeric(longitude)),
      gn_accuracy = suppressWarnings(as.numeric(accuracy))
    ) |>
    dplyr::filter(!is.na(pc_norm), !is.na(gn_lat)) |>
    dplyr::group_by(pc_norm) |>
    dplyr::slice(1L) |>
    dplyr::ungroup() |>
    dplyr::select(pc_norm, gn_lat, gn_lon, gn_accuracy,
                  gn_place_name = place_name)
  message(sprintf("  %s GeoNames Ontario codes",
                  format(nrow(gn_on), big.mark = ",")))

  message("[centroids] Step 4/5: Merging NAR + GeoNames")
  combined <- dplyr::full_join(nar_centroids, gn_on, by = "pc_norm") |>
    dplyr::mutate(
      in_nar = !is.na(addr_count),
      in_geonames = !is.na(gn_lat),
      point_source = dplyr::case_when(
        in_nar & !is.na(nar_lat) ~ "nar_centroid",
        in_geonames ~ "geonames",
        TRUE ~ "none"
      ),
      point_method = dplyr::case_when(
        point_source == "nar_centroid" ~ "nar_address_mean_wgs84",
        point_source == "geonames" ~ "geonames_direct_wgs84",
        TRUE ~ "none"
      ),
      latitude = dplyr::case_when(
        point_source == "nar_centroid" ~ nar_lat,
        point_source == "geonames" ~ gn_lat,
        TRUE ~ NA_real_
      ),
      longitude = dplyr::case_when(
        point_source == "nar_centroid" ~ nar_lon,
        point_source == "geonames" ~ gn_lon,
        TRUE ~ NA_real_
      ),
      nar_release_date = ifelse(in_nar, "2026-06-26", NA_character_),
      nar_catalogue = ifelse(in_nar, "46-26-0002", NA_character_),
      nar_licence = ifelse(in_nar, "OGL-Canada", NA_character_),
      gn_retrieval_date = ifelse(in_geonames, "2026-07-17", NA_character_),
      gn_licence = ifelse(in_geonames, "CC BY 4.0", NA_character_),
      gn_attribution = ifelse(
        in_geonames,
        "Data from GeoNames (geonames.org), CC BY 4.0", NA_character_
      )
    ) |>
    dplyr::select(
      postal_code = pc_norm, latitude, longitude, point_source, point_method,
      in_nar, in_geonames, nar_lat, nar_lon,
      nar_address_count = addr_count, nar_addr_with_coords = addr_with_coords,
      nar_release_date, nar_catalogue, nar_licence,
      gn_lat, gn_lon, gn_accuracy, gn_place_name,
      gn_retrieval_date, gn_licence, gn_attribution
    ) |>
    dplyr::arrange(postal_code)

  message(sprintf(
    "  %s total codes | nar_centroid: %s | geonames: %s | none: %s",
    format(nrow(combined), big.mark = ","),
    format(sum(combined$point_source == "nar_centroid"), big.mark = ","),
    format(sum(combined$point_source == "geonames"), big.mark = ","),
    format(sum(combined$point_source == "none"), big.mark = ",")
  ))

  message("[centroids] Step 5/5: Writing ", out_csv)
  readr::write_csv(combined, out_csv)
  message("[centroids] Done: ", out_csv)
  invisible(out_csv)
}

#' Assign postal centroids to Dissemination Blocks and join GAF
#'
#' Validates that centroids fall within the Ontario boundary, assigns
#' each to exactly one 2021 Dissemination Block via point-in-polygon,
#' and joins the Geographic Attribute File for higher geographies.
#'
#' @param centroids_csv Path returned by [build_centroids()].
#' @param province_shp Path to the province boundary `.shp` from
#'   [download_census_boundaries()].
#' @param db_shp Path to the DB boundary `.shp` from
#'   [download_census_boundaries()].
#' @param gaf_csv Path returned by [download_gaf()].
#' @param output_dir Directory for output files. Defaults to
#'   `postal_centroids` inside the build cache.
#' @return Invisibly, the path to `ontario_postal_gaf_rollup.csv`.
#' @export
build_db_assignment <- function(centroids_csv, province_shp, db_shp,
                                gaf_csv, output_dir = NULL) {
  .check_build_deps(need_sf = TRUE)
  if (is.null(output_dir)) {
    output_dir <- file.path(.opcc_build_cache(NULL), "postal_centroids")
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  out_csv <- file.path(output_dir, "ontario_postal_gaf_rollup.csv")

  message("[db-assign] Step 1/4: Loading centroids from ", centroids_csv)
  pc_df <- readr::read_csv(centroids_csv, show_col_types = FALSE)
  pc_clean <- pc_df[!is.na(pc_df$longitude) & !is.na(pc_df$latitude), ]
  message(sprintf("  %d points with coordinates (%d dropped)",
                  nrow(pc_clean), nrow(pc_df) - nrow(pc_clean)))

  message("[db-assign] Step 2/4: Loading boundary shapefiles")
  province_sf <- sf::st_read(province_shp, quiet = TRUE)
  db_sf <- sf::st_read(db_shp, quiet = TRUE)
  message(sprintf("  Ontario DB polygons: %d",
                  sum(as.character(db_sf$PRUID) == "35", na.rm = TRUE)))

  message("[db-assign] Step 3/4: Ontario validation and DB assignment")
  pc_db_df <- .assign_ontario_points(pc_clean, province_sf, db_sf)
  report <- attr(pc_db_df, "opcc_spatial_validation")
  message(sprintf("  matched: %d | unmatched: %d",
                  report$matched_points, report$unmatched_points))

  message("[db-assign] Step 4/4: GAF rollup")
  gaf_df <- readr::read_csv(
    gaf_csv, col_types = readr::cols(.default = "c"), show_col_types = FALSE
  )
  gaf_db <- .first_column(gaf_df, c("DBUID_IDIDU", "DBUID"), "GAF DBUID")
  if (anyDuplicated(gaf_df[[gaf_db]])) {
    stop("GAF contains duplicate DBUID rows", call. = FALSE)
  }
  final_rollup <- dplyr::left_join(
    pc_db_df, gaf_df, by = stats::setNames(gaf_db, "DBUID")
  )
  dauid_col <- .first_column(gaf_df, c("DAUID_ADIDU", "DAUID"), "GAF DAUID")
  matched <- pc_db_df$db_match_status == "matched_2021_ontario_db"
  if (any(matched & (is.na(final_rollup[[dauid_col]]) |
                     !nzchar(final_rollup[[dauid_col]])))) {
    stop("Some matched Ontario DBs have no GAF DAUID", call. = FALSE)
  }
  .validate_point_geography(final_rollup, dauid_col)

  message("[db-assign] Writing ", out_csv)
  readr::write_csv(final_rollup, out_csv)
  message("[db-assign] Done: ", out_csv)
  invisible(out_csv)
}

.aggregate_m2_evidence <- function(data, geography_columns = character()) {
  required <- c("postal_code", "LOC_GUID", "DBUID")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop("Missing required columns: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  valid <- data[
    !is.na(data$postal_code) & data$postal_code != "" &
      !is.na(data$LOC_GUID) & data$LOC_GUID != "" &
      !is.na(data$DBUID) & data$DBUID != "", , drop = FALSE
  ]
  if (nrow(valid) == 0L) stop("No valid NAR observations", call. = FALSE)

  key <- paste(valid$postal_code, valid$DBUID, sep = "\r")
  groups <- split(seq_len(nrow(valid)), key, drop = TRUE)
  rows <- lapply(groups, function(index) {
    first <- valid[index[1L], , drop = FALSE]
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

  order_index <- order(result$postal_code, -result$n_unique_addresses,
                       result$DBUID)
  result <- result[order_index, , drop = FALSE]
  result$address_weight <- ave(
    result$n_unique_addresses, result$postal_code,
    FUN = function(x) x / sum(x)
  )
  result$confidence <- result$address_weight
  result$best_link <- as.logical(ave(
    seq_len(nrow(result)), result$postal_code,
    FUN = function(x) seq_along(x) == 1L
  ))

  sums <- tapply(result$address_weight, result$postal_code, sum)
  if (any(abs(sums - 1) > 1e-8)) {
    stop("M2 weights do not sum to 1 per postal code", call. = FALSE)
  }
  if (anyDuplicated(result[c("postal_code", "DBUID")])) {
    stop("M2 contains duplicate postal_code/DBUID keys", call. = FALSE)
  }
  result
}

.append_geonames_supplementary <- function(nar_result, rollup_path,
                                           geography_columns) {
  if (!file.exists(rollup_path)) {
    stop("Missing GAF rollup: ", rollup_path,
         "\nRun build_db_assignment() first.", call. = FALSE)
  }
  rollup <- readr::read_csv(
    rollup_path, col_types = readr::cols(.default = "c"),
    show_col_types = FALSE, name_repair = "minimal"
  )
  required <- c("postal_code", "point_source", "DBUID", "DAUID_ADIDU",
                "db_match_status", "latitude", "longitude", "gn_accuracy")
  missing <- setdiff(required, names(rollup))
  if (length(missing) > 0L) {
    stop("Rollup is missing required GeoNames fields: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  geonames <- rollup[rollup$point_source == "geonames", , drop = FALSE]
  point_report <- .validate_point_geography(geonames)
  matched_status <- geonames$db_match_status == "matched_2021_ontario_db"
  geo <- geonames[
    matched_status &
      !is.na(geonames$postal_code) & geonames$postal_code != "" &
      !is.na(geonames$latitude) & !is.na(geonames$longitude) &
      !is.na(geonames$gn_accuracy), , drop = FALSE
  ]
  geo <- geo[!(geo$postal_code %in% nar_result$postal_code), , drop = FALSE]
  if (anyDuplicated(geo$postal_code)) {
    stop("GeoNames supplementary must be one point per postal code",
         call. = FALSE)
  }

  supplementary <- data.frame(
    postal_code = as.character(geo$postal_code),
    DBUID = as.character(geo$DBUID),
    n_observations = 0L,
    n_unique_addresses = 0L,
    n_sources = 1L,
    address_weight = NA_real_,
    best_link = TRUE,
    confidence = NA_real_,
    source_vintage = "2026-07-17",
    census_vintage = "2021",
    evidence_class = "geonames_supplementary",
    assignment_method = "geonames_point_in_polygon",
    allocation_weight = 1,
    gn_accuracy = suppressWarnings(as.numeric(geo$gn_accuracy)),
    stringsAsFactors = FALSE
  )
  for (column in geography_columns) {
    source_column <- if (column == "DAUID") "DAUID_ADIDU" else column
    supplementary[[column]] <- if (source_column %in% names(geo)) {
      as.character(geo[[source_column]])
    } else {
      NA_character_
    }
  }
  supplementary <- supplementary[, c(
    "postal_code", "DBUID", geography_columns,
    "n_observations", "n_unique_addresses", "n_sources",
    "address_weight", "best_link", "confidence",
    "source_vintage", "census_vintage", "evidence_class",
    "assignment_method", "allocation_weight", "gn_accuracy"
  ), drop = FALSE]

  nar_result$evidence_class <- "nar_address"
  nar_result$assignment_method <- "nar_address_point_in_polygon"
  nar_result$allocation_weight <- nar_result$address_weight
  nar_result$gn_accuracy <- NA_real_
  combined <- rbind(nar_result[, names(supplementary), drop = FALSE],
                    supplementary)
  combined <- combined[order(combined$postal_code, -combined$best_link,
                             -combined$allocation_weight, combined$DBUID), ,
                       drop = FALSE]
  rownames(combined) <- NULL
  attr(combined, "opcc_point_assignment_report") <- point_report
  combined
}

#' Build the M2 postal-code-to-DB correspondence
#'
#' Reads raw NAR address points, assigns them to 2021 Dissemination
#' Blocks via point-in-polygon, joins the GAF, aggregates evidence per
#' postal-code/DB pair, and appends GeoNames supplementary links from
#' the rollup produced by [build_db_assignment()].
#'
#' @param nar_dir Path returned by [download_nar()].
#' @param db_shp Path to the DB boundary `.shp` from
#'   [download_census_boundaries()].
#' @param gaf_csv Path returned by [download_gaf()].
#' @param rollup_csv Path returned by [build_db_assignment()].
#' @param output_dir Directory for output files. Defaults to `m2`
#'   inside the build cache.
#' @return Invisibly, the path to `m2_correspondence.csv`.
#' @export
build_m2 <- function(nar_dir, db_shp, gaf_csv, rollup_csv,
                     output_dir = NULL) {
  .check_build_deps(need_sf = TRUE)
  if (is.null(output_dir)) {
    output_dir <- file.path(.opcc_build_cache(NULL), "m2")
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  out_csv <- file.path(output_dir, "m2_correspondence.csv")
  manifest_path <- file.path(output_dir, "m2_manifest.json")

  message("[m2] Step 1/6: Reading NAR Address and Location files")
  addr_parts <- sort(list.files(
    file.path(nar_dir, "Addresses"), "^Address_35_.*[.]csv$",
    full.names = TRUE
  ))
  loc_parts <- sort(list.files(
    file.path(nar_dir, "Locations"), "^Location_35_.*[.]csv$",
    full.names = TRUE
  ))
  if (length(addr_parts) == 0L || length(loc_parts) == 0L) {
    stop("Missing NAR Ontario part files in ", nar_dir, call. = FALSE)
  }
  read_all <- function(paths, cols) {
    dplyr::bind_rows(lapply(paths, function(p) {
      message("  reading ", basename(p))
      .read_nar_csv(p, cols)
    }))
  }
  addresses <- read_all(addr_parts, c("LOC_GUID", "MAIL_POSTAL_CODE"))
  locations <- read_all(loc_parts, c(
    "LOC_GUID", "BF_REPPOINT_LATITUDE", "BF_REPPOINT_LONGITUDE",
    "BG_LATITUDE", "BG_LONGITUDE"
  ))

  message("[m2] Step 2/6: Joining addresses to locations")
  locations$latitude <- suppressWarnings(
    as.numeric(locations$BF_REPPOINT_LATITUDE))
  locations$longitude <- suppressWarnings(
    as.numeric(locations$BF_REPPOINT_LONGITUDE))
  fallback_lat <- is.na(locations$latitude)
  fallback_lon <- is.na(locations$longitude)
  locations$latitude[fallback_lat] <- suppressWarnings(
    as.numeric(locations$BG_LATITUDE[fallback_lat]))
  locations$longitude[fallback_lon] <- suppressWarnings(
    as.numeric(locations$BG_LONGITUDE[fallback_lon]))
  locations <- locations[, c("LOC_GUID", "latitude", "longitude")]

  addresses$postal_code <- normalize_postal_code(addresses$MAIL_POSTAL_CODE)
  addresses$LOC_GUID <- as.character(addresses$LOC_GUID)
  address_located <- dplyr::left_join(
    addresses[, c("LOC_GUID", "postal_code")], locations, by = "LOC_GUID"
  )
  address_located$latitude <- as.numeric(address_located$latitude)
  address_located$longitude <- as.numeric(address_located$longitude)
  address_located <- address_located[
    !is.na(address_located$latitude) & !is.na(address_located$longitude), ,
    drop = FALSE
  ]
  if (nrow(address_located) == 0L) {
    stop("No NAR observations have usable coordinates", call. = FALSE)
  }
  message(sprintf("  %s located address rows",
                  format(nrow(address_located), big.mark = ",")))

  message("[m2] Step 3/6: Point-in-polygon DB assignment")
  points <- sf::st_as_sf(
    address_located, coords = c("longitude", "latitude"),
    crs = 4326, remove = FALSE
  )
  db <- sf::st_read(db_shp, quiet = TRUE)
  db <- db[as.character(db$PRUID) == "35", c("DBUID", "geometry")]
  points <- sf::st_transform(points, sf::st_crs(db))
  joined <- sf::st_join(points, db, join = sf::st_intersects, left = FALSE)
  joined <- sf::st_drop_geometry(joined)
  joined$DBUID <- as.character(joined$DBUID)
  if (nrow(joined) == 0L) {
    stop("No observations intersect Ontario DB polygons", call. = FALSE)
  }
  point_matches <- dplyr::summarise(
    dplyr::group_by(joined, LOC_GUID),
    n_dbuid = dplyr::n_distinct(DBUID), .groups = "drop"
  )
  if (any(point_matches$n_dbuid > 1L)) {
    stop("Some points intersect multiple DBUID polygons", call. = FALSE)
  }
  message(sprintf("  %s DB-assigned observations",
                  format(nrow(joined), big.mark = ",")))

  message("[m2] Step 4/6: GAF join")
  gaf <- readr::read_csv(
    gaf_csv, col_types = readr::cols(.default = "c"),
    show_col_types = FALSE, name_repair = "minimal"
  )
  gaf_db <- .first_column(gaf, c("DBUID_IDIDU", "DBUID"), "GAF DBUID")
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
    geography_specs,
    function(candidates) any(candidates %in% names(gaf)),
    logical(1)
  )]
  if (!"DAUID" %in% geography_columns) stop("GAF must contain DAUID",
                                            call. = FALSE)
  gaf_map <- data.frame(DBUID = as.character(gaf[[gaf_db]]),
                        stringsAsFactors = FALSE)
  for (column in geography_columns) {
    source_column <- .first_column(gaf, geography_specs[[column]], column)
    gaf_map[[column]] <- as.character(gaf[[source_column]])
  }
  if (anyDuplicated(gaf_map$DBUID)) stop("GAF has duplicate DBUID rows",
                                         call. = FALSE)
  joined <- dplyr::left_join(joined, gaf_map, by = "DBUID")
  if (anyNA(joined$DAUID)) stop("Some DBUID observations have no GAF DAUID",
                                call. = FALSE)

  message("[m2] Step 5/6: Aggregating evidence and appending GeoNames")
  result <- .aggregate_m2_evidence(joined, geography_columns)
  result$source_vintage <- "2026-06-26"
  result$census_vintage <- "2021"
  result <- result[, c(
    "postal_code", "DBUID", geography_columns, "n_observations",
    "n_unique_addresses", "n_sources", "address_weight", "best_link",
    "confidence", "source_vintage", "census_vintage"
  ), drop = FALSE]
  result <- .append_geonames_supplementary(result, rollup_csv,
                                           geography_columns)
  point_report <- attr(result, "opcc_point_assignment_report")

  if (anyDuplicated(result[c("postal_code", "DBUID")])) {
    stop("M2 contains duplicate postal_code/DBUID keys", call. = FALSE)
  }
  weights <- tapply(result$allocation_weight, result$postal_code, sum)
  if (any(abs(weights - 1) > 1e-8)) {
    stop("M2 allocation weights do not sum to 1", call. = FALSE)
  }
  best <- table(result$postal_code[result$best_link])
  if (any(best != 1L)) {
    stop("M2 must have exactly one best link per postal code", call. = FALSE)
  }

  message("[m2] Step 6/6: Writing output")
  readr::write_csv(result, out_csv)
  code_version <- tryCatch(
    system2("git", c("rev-parse", "HEAD"), stdout = TRUE,
            stderr = FALSE)[1],
    error = function(e) NA_character_
  )
  manifest <- list(
    source_vintage = list(nar = "2026-06-26", geonames = "2026-07-17"),
    census_vintage = "2021",
    code_version = code_version,
    build_timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ",
                                 tz = "UTC"),
    row_counts = list(
      correspondence_rows = nrow(result),
      input_observations = nrow(joined),
      geonames_supplementary_rows = sum(
        result$evidence_class == "geonames_supplementary"),
      geonames_matched_points = point_report$matched_points,
      geonames_unmatched_points = point_report$unmatched_points
    ),
    validation_results = list(
      weights_sum_to_one = TRUE,
      unique_best_link = TRUE,
      unique_postal_dbuid = TRUE,
      restricted_sources_used = FALSE
    )
  )
  jsonlite::write_json(manifest, manifest_path, pretty = TRUE,
                       auto_unbox = TRUE)
  message(sprintf("[m2] Done: %d rows, %d postal codes -> %s",
                  nrow(result), length(unique(result$postal_code)), out_csv))
  invisible(out_csv)
}
