# tests/testthat/helper-sli-validation.R
#
# Shared helper functions for the SLI/PCCF validation pipeline and its tests.
# This file is auto-sourced by testthat and is also sourced by
# scripts/sli_validate.R.  It defines only pure functions; it does not run a
# CLI or touch restricted data.
#
# All exported names carry the sli_ prefix to avoid collisions with package
# functions (e.g. normalize_postal_code).

library(readr)
library(dplyr)
library(jsonlite)
library(digest)

sli_normalize_postal_code <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- gsub("[[:space:]]+", "", x)
  ifelse(nchar(x) == 6L,
         paste0(substr(x, 1, 3), " ", substr(x, 4, 6)),
         x)
}

sli_haversine_km <- function(lat1, lon1, lat2, lon2) {
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 +
    cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  6371 * c
}

sli_read_centroids <- function(path) {
  if (!file.exists(path)) stop("Centroid file not found: ", path)
  df <- readr::read_csv(path, show_col_types = FALSE)
  req <- c("postal_code", "latitude", "longitude", "point_source")
  miss <- setdiff(req, names(df))
  if (length(miss) > 0) {
    stop("Missing required centroid columns: ", paste(miss, collapse = ", "))
  }
  df$postal_code <- sli_normalize_postal_code(df$postal_code)
  df <- df %>%
    filter(!is.na(latitude), !is.na(longitude)) %>%
    distinct(postal_code, .keep_all = TRUE)
  df
}

sli_read_sli <- function(path) {
  if (!file.exists(path)) stop("SLI file not found: ", path)
  df <- readr::read_csv(path, show_col_types = FALSE)
  nms <- tolower(names(df))
  pc_candidates <- c("postal_code", "postalcode", "pc", "mail_postal_code",
                     "postal_cd")
  lat_candidates <- c("latitude", "lat")
  lon_candidates <- c("longitude", "lon", "long")
  pc_col <- names(df)[match(pc_candidates, nms, nomatch = 0)]
  lat_col <- names(df)[match(lat_candidates, nms, nomatch = 0)]
  lon_col <- names(df)[match(lon_candidates, nms, nomatch = 0)]
  if (length(pc_col) == 0 || length(lat_col) == 0 || length(lon_col) == 0) {
    stop("SLI CSV must contain postal-code, latitude, and longitude columns.")
  }
  df <- df %>%
    select(postal_code = all_of(pc_col[1]),
           latitude    = all_of(lat_col[1]),
           longitude   = all_of(lon_col[1])) %>%
    mutate(postal_code = sli_normalize_postal_code(postal_code),
           latitude    = suppressWarnings(as.numeric(latitude)),
           longitude   = suppressWarnings(as.numeric(longitude))) %>%
    filter(!is.na(latitude), !is.na(longitude)) %>%
    distinct(postal_code, .keep_all = TRUE)
  df
}

sli_make_synthetic_qa <- function(centroids, seed = 42L, n_per_source = 100L) {
  set.seed(seed)
  out <- centroids %>%
    group_by(point_source) %>%
    slice_sample(n = n_per_source) %>%
    ungroup() %>%
    mutate(
      lat_noise = case_when(
        point_source == "nar_centroid" ~ rnorm(n(), 0, 0.001),
        point_source == "geonames"     ~ rnorm(n(), 0, 0.02),
        TRUE                           ~ rnorm(n(), 0, 0.05)
      ),
      lon_noise = case_when(
        point_source == "nar_centroid" ~ rnorm(n(), 0, 0.001),
        point_source == "geonames"     ~ rnorm(n(), 0, 0.02),
        TRUE                           ~ rnorm(n(), 0, 0.05)
      ),
      latitude  = latitude + lat_noise,
      longitude = longitude + lon_noise
    ) %>%
    select(postal_code, latitude, longitude)
  out
}

sli_compute_metrics <- function(centroids, sli) {
  joined <- centroids %>%
    inner_join(sli, by = "postal_code", suffix = c("", "_sli"))

  joined <- joined %>%
    mutate(distance_km = sli_haversine_km(latitude, longitude,
                                        latitude_sli, longitude_sli))

  overall <- joined %>%
    summarise(
      n                     = n(),
      median_distance_km    = median(distance_km, na.rm = TRUE),
      mean_distance_km      = mean(distance_km, na.rm = TRUE),
      p90_distance_km       = quantile(distance_km, 0.90, na.rm = TRUE),
      p95_distance_km       = quantile(distance_km, 0.95, na.rm = TRUE),
      p99_distance_km       = quantile(distance_km, 0.99, na.rm = TRUE),
      max_distance_km       = max(distance_km, na.rm = TRUE)
    )

  by_source <- joined %>%
    group_by(point_source) %>%
    summarise(
      n                     = n(),
      median_distance_km    = median(distance_km, na.rm = TRUE),
      mean_distance_km      = mean(distance_km, na.rm = TRUE),
      p90_distance_km       = quantile(distance_km, 0.90, na.rm = TRUE),
      p95_distance_km       = quantile(distance_km, 0.95, na.rm = TRUE),
      p99_distance_km       = quantile(distance_km, 0.99, na.rm = TRUE),
      max_distance_km       = max(distance_km, na.rm = TRUE),
      .groups = "drop"
    )

  coverage <- list(
    distinct_open_postal_codes   = n_distinct(centroids$postal_code),
    distinct_sli_postal_codes    = n_distinct(sli$postal_code),
    matched_postal_codes         = n_distinct(joined$postal_code),
    coverage_pct                 = 100 * n_distinct(joined$postal_code) /
      n_distinct(sli$postal_code)
  )

  list(
    overall    = as.list(overall),
    by_source  = by_source,
    coverage   = coverage,
    joined_n   = nrow(joined)
  )
}
