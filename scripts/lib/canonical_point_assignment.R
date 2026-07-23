assign_canonical_ontario_points <- function(
    points,
    province_boundaries,
    db_boundaries) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("Canonical point assignment requires the sf package", call. = FALSE)
  }
  required_points <- c("latitude", "longitude")
  if (!is.data.frame(points) ||
      !all(required_points %in% names(points))) {
    stop(
      "points must be a data frame containing latitude and longitude",
      call. = FALSE
    )
  }
  latitude <- suppressWarnings(as.numeric(points$latitude))
  longitude <- suppressWarnings(as.numeric(points$longitude))
  if (any(!is.finite(latitude) | !is.finite(longitude))) {
    stop("Canonical points must have finite coordinates", call. = FALSE)
  }
  if (!inherits(province_boundaries, "sf") ||
      !"PRUID" %in% names(province_boundaries)) {
    stop("province_boundaries must be an sf object containing PRUID", call. = FALSE)
  }
  if (!inherits(db_boundaries, "sf") ||
      !all(c("PRUID", "DBUID") %in% names(db_boundaries))) {
    stop(
      "db_boundaries must be an sf object containing PRUID and DBUID",
      call. = FALSE
    )
  }
  if (is.na(sf::st_crs(province_boundaries)) ||
      is.na(sf::st_crs(db_boundaries))) {
    stop("Boundary inputs must declare coordinate reference systems", call. = FALSE)
  }

  ontario_boundary <- province_boundaries[
    as.character(province_boundaries$PRUID) == "35",
    ,
    drop = FALSE
  ]
  ontario_db <- db_boundaries[
    as.character(db_boundaries$PRUID) == "35",
    "DBUID",
    drop = FALSE
  ]
  if (nrow(ontario_boundary) == 0L) {
    stop("province_boundaries has no Ontario PRUID 35 geometry", call. = FALSE)
  }
  if (nrow(ontario_db) == 0L) {
    stop("db_boundaries has no Ontario PRUID 35 geometry", call. = FALSE)
  }
  if (anyNA(ontario_db$DBUID) ||
      any(!nzchar(trimws(as.character(ontario_db$DBUID))))) {
    stop("Ontario DB polygons must have non-empty DBUID values", call. = FALSE)
  }

  point_sf <- sf::st_as_sf(
    transform(points, latitude = latitude, longitude = longitude),
    coords = c("longitude", "latitude"),
    crs = 4326,
    remove = FALSE
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
    province_points,
    province_geometry
  )) > 0L
  if (any(!inside_ontario)) {
    stop(
      sprintf(
        "%d canonical point(s) fall outside the Ontario boundary",
        sum(!inside_ontario)
      ),
      call. = FALSE
    )
  }

  db_crs <- if (sf::st_is_longlat(ontario_db)) {
    sf::st_crs(3347)
  } else {
    sf::st_crs(ontario_db)
  }
  ontario_db <- sf::st_transform(ontario_db, db_crs)
  db_points <- sf::st_transform(point_sf, db_crs)
  db_matches <- sf::st_intersects(
    db_points,
    ontario_db
  )
  match_counts <- lengths(db_matches)
  if (any(match_counts > 1L)) {
    stop(
      sprintf(
        "%d canonical point(s) intersect multiple 2021 Ontario DBs",
        sum(match_counts > 1L)
      ),
      call. = FALSE
    )
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
    matched,
    "matched_2021_ontario_db",
    "unmatched_no_2021_ontario_db"
  )
  attr(out, "opcc_spatial_validation") <- list(
    input_points = nrow(points),
    matched_points = sum(matched),
    unmatched_points = sum(!matched),
    outside_ontario_points = 0L
  )
  out
}

validate_canonical_point_geography <- function(
    points,
    dauid_column = "DAUID_ADIDU") {
  required <- c("DBUID", dauid_column, "db_match_status")
  if (!is.data.frame(points) || !all(required %in% names(points))) {
    stop(
      paste(
        "points must contain DBUID, db_match_status, and",
        dauid_column
      ),
      call. = FALSE
    )
  }
  allowed_status <- c(
    "matched_2021_ontario_db",
    "unmatched_no_2021_ontario_db"
  )
  if (anyNA(points$db_match_status) ||
      any(!points$db_match_status %in% allowed_status)) {
    stop("points contains an unknown db_match_status", call. = FALSE)
  }
  has_db <- !is.na(points$DBUID) &
    nzchar(trimws(as.character(points$DBUID)))
  has_da <- !is.na(points[[dauid_column]]) &
    nzchar(trimws(as.character(points[[dauid_column]])))
  matched <- points$db_match_status == "matched_2021_ontario_db"
  if (any(matched != (has_db & has_da))) {
    stop(
      "db_match_status is inconsistent with DBUID/DAUID nullability",
      call. = FALSE
    )
  }
  list(
    input_points = nrow(points),
    matched_points = sum(matched),
    unmatched_points = sum(!matched)
  )
}
