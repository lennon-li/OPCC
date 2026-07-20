# tests/testthat/helper-sli-validation.R
#
# Shared helper functions for the SLI/PCCF validation pipeline and its tests.
# This file is auto-sourced by testthat and is also sourced by
# scripts/sli_validate.R and scripts/m1_release.R. It defines only pure
# functions; it does not run a CLI or touch restricted data.
#
# All exported names carry the sli_ prefix to avoid collisions with package
# functions (e.g. normalize_postal_code).

# Deliberate dependency boundary: these packages are used only inside the
# helper functions and the scripts that source this file. All calls are
# namespace-qualified to avoid relying on the search path.

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
    dplyr::filter(!is.na(latitude), !is.na(longitude)) %>%
    dplyr::distinct(postal_code, .keep_all = TRUE)
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
    dplyr::select(postal_code = dplyr::all_of(pc_col[1]),
                  latitude    = dplyr::all_of(lat_col[1]),
                  longitude   = dplyr::all_of(lon_col[1])) %>%
    dplyr::mutate(postal_code = sli_normalize_postal_code(postal_code),
                  latitude    = suppressWarnings(as.numeric(latitude)),
                  longitude   = suppressWarnings(as.numeric(longitude))) %>%
    dplyr::filter(!is.na(latitude), !is.na(longitude)) %>%
    dplyr::distinct(postal_code, .keep_all = TRUE)
  df
}

sli_make_synthetic_qa <- function(centroids, seed = 42L, n_per_source = 100L) {
  set.seed(seed)
  out <- centroids %>%
    dplyr::group_by(point_source) %>%
    dplyr::slice_sample(n = n_per_source) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      lat_noise = dplyr::case_when(
        point_source == "nar_centroid" ~ stats::rnorm(dplyr::n(), 0, 0.001),
        point_source == "geonames"     ~ stats::rnorm(dplyr::n(), 0, 0.02),
        TRUE                           ~ stats::rnorm(dplyr::n(), 0, 0.05)
      ),
      lon_noise = dplyr::case_when(
        point_source == "nar_centroid" ~ stats::rnorm(dplyr::n(), 0, 0.001),
        point_source == "geonames"     ~ stats::rnorm(dplyr::n(), 0, 0.02),
        TRUE                           ~ stats::rnorm(dplyr::n(), 0, 0.05)
      ),
      latitude  = latitude + lat_noise,
      longitude = longitude + lon_noise
    ) %>%
    dplyr::select(postal_code, latitude, longitude)
  out
}

sli_compute_metrics <- function(centroids, sli) {
  joined <- centroids %>%
    dplyr::inner_join(sli, by = "postal_code", suffix = c("", "_sli"))

  joined <- joined %>%
    dplyr::mutate(distance_km = sli_haversine_km(latitude, longitude,
                                                 latitude_sli, longitude_sli))

  overall <- joined %>%
    dplyr::summarise(
      n                     = dplyr::n(),
      median_distance_km    = stats::median(distance_km, na.rm = TRUE),
      mean_distance_km      = base::mean(distance_km, na.rm = TRUE),
      p90_distance_km       = stats::quantile(distance_km, 0.90, na.rm = TRUE),
      p95_distance_km       = stats::quantile(distance_km, 0.95, na.rm = TRUE),
      p99_distance_km       = stats::quantile(distance_km, 0.99, na.rm = TRUE),
      max_distance_km       = base::max(distance_km, na.rm = TRUE)
    )

  by_source <- joined %>%
    dplyr::group_by(point_source) %>%
    dplyr::summarise(
      n                     = dplyr::n(),
      median_distance_km    = stats::median(distance_km, na.rm = TRUE),
      mean_distance_km      = base::mean(distance_km, na.rm = TRUE),
      p90_distance_km       = stats::quantile(distance_km, 0.90, na.rm = TRUE),
      p95_distance_km       = stats::quantile(distance_km, 0.95, na.rm = TRUE),
      p99_distance_km       = stats::quantile(distance_km, 0.99, na.rm = TRUE),
      max_distance_km       = base::max(distance_km, na.rm = TRUE),
      .groups = "drop"
    )

  coverage <- list(
    distinct_open_postal_codes   = dplyr::n_distinct(centroids$postal_code),
    distinct_sli_postal_codes    = dplyr::n_distinct(sli$postal_code),
    matched_postal_codes         = dplyr::n_distinct(joined$postal_code),
    coverage_pct                 = 100 * dplyr::n_distinct(joined$postal_code) /
      dplyr::n_distinct(sli$postal_code)
  )

  list(
    overall    = as.list(overall),
    by_source  = by_source,
    coverage   = coverage,
    joined_n   = nrow(joined)
  )
}

# Verify a released M1 centroid artifact against its manifest.
#
# manifest: a list with an `artifact` element containing at least
#   csv_sha256, gz_sha256, total_rows, and schema$columns.
# Returns the decompressed centroid data frame invisibly.
sli_verify_m1_artifact <- function(gz_path, manifest) {
  if (!file.exists(gz_path)) {
    stop("M1 artifact not found: ", gz_path)
  }

  art <- manifest$artifact
  if (is.null(art)) {
    stop("Manifest has no artifact section")
  }

  gz_bytes <- readBin(gz_path, what = raw(), n = file.info(gz_path)$size)
  gz_sha256 <- digest::digest(gz_bytes, algo = "sha256", serialize = FALSE)
  if (!identical(gz_sha256, art$gz_sha256)) {
    stop("M1 gzip hash mismatch: expected ", art$gz_sha256,
         ", got ", gz_sha256)
  }

  csv_bytes <- memDecompress(gz_bytes, type = "gzip")
  csv_sha256 <- digest::digest(csv_bytes, algo = "sha256", serialize = FALSE)
  if (!identical(csv_sha256, art$csv_sha256)) {
    stop("M1 decompressed CSV hash mismatch: expected ", art$csv_sha256,
         ", got ", csv_sha256)
  }

  con <- rawConnection(csv_bytes, "r")
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  df <- readr::read_csv(con, show_col_types = FALSE)

  req_cols <- art$schema$columns
  if (is.null(req_cols)) {
    req_cols <- c("postal_code", "latitude", "longitude", "point_source")
  }
  miss <- setdiff(req_cols, names(df))
  if (length(miss) > 0) {
    stop("M1 schema missing columns: ", paste(miss, collapse = ", "))
  }

  if (nrow(df) != art$total_rows) {
    stop("M1 row count mismatch: expected ", art$total_rows,
         ", got ", nrow(df))
  }

  invisible(df)
}

# Validate that a producer revision exists and contains every named generator
# script. Returns the full SHA invisibly.
sli_validate_producer_ref <- function(producer_ref, scripts) {
  if (is.null(producer_ref) || !nzchar(producer_ref)) {
    stop("--producer-ref is required.")
  }
  res <- tryCatch(
    suppressWarnings(
      system2("git", c("cat-file", "-e", producer_ref),
              stdout = TRUE, stderr = TRUE)
    ),
    error = function(e) e
  )
  if (inherits(res, "error") || !is.null(attr(res, "status"))) {
    stop("Producer revision not found: ", producer_ref)
  }
  for (s in scripts) {
    res2 <- tryCatch(
      suppressWarnings(
        system2("git", c("cat-file", "-e", paste0(producer_ref, ":", s)),
                stdout = TRUE, stderr = TRUE)
      ),
      error = function(e) e
    )
    if (inherits(res2, "error") || !is.null(attr(res2, "status"))) {
      stop("Producer revision ", producer_ref,
           " does not contain script: ", s)
    }
  }
  invisible(producer_ref)
}
