# R/validation-metrics.R
#
# Pure metric and verification functions for local benchmark validation.
# This file does not run a CLI, write outputs, or retain restricted row data
# in aggregate metric results.
#
# Names retain the sli_ prefix for compatibility with the existing validation
# workflow.

# Deliberate dependency boundary: these packages are used only inside the
# helper functions and the scripts that source this file. All calls are
# namespace-qualified to avoid relying on the search path.

utils::globalVariables(c(
  "distance_km",
  "lat_noise",
  "latitude",
  "latitude_sli",
  "lon_noise",
  "longitude",
  "longitude_sli",
  "point_source",
  "postal_code"
))

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
  df <- df |>
    dplyr::filter(!is.na(latitude), !is.na(longitude)) |>
    dplyr::distinct(
      postal_code,
      latitude,
      longitude,
      point_source,
      .keep_all = TRUE
    )
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
  df <- df |>
    dplyr::select(postal_code = dplyr::all_of(pc_col[1]),
                  latitude    = dplyr::all_of(lat_col[1]),
                  longitude   = dplyr::all_of(lon_col[1])) |>
    dplyr::mutate(postal_code = sli_normalize_postal_code(postal_code),
                  latitude    = suppressWarnings(as.numeric(latitude)),
                  longitude   = suppressWarnings(as.numeric(longitude))) |>
    dplyr::filter(!is.na(latitude), !is.na(longitude)) |>
    dplyr::distinct(postal_code, latitude, longitude)
  df
}

sli_make_synthetic_qa <- function(centroids, seed = 42L, n_per_source = 100L) {
  set.seed(seed)
  out <- centroids |>
    dplyr::group_by(point_source) |>
    dplyr::slice_sample(n = n_per_source) |>
    dplyr::ungroup() |>
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
    ) |>
    dplyr::select(postal_code, latitude, longitude)
  out
}

sli_compute_point_distances <- function(centroids, sli) {
  centroids$.opcc_row <- seq_len(nrow(centroids))
  joined <- merge(
    centroids,
    sli,
    by = "postal_code",
    suffixes = c("", "_sli"),
    sort = FALSE
  )
  joined <- joined |>
    dplyr::mutate(distance_km = sli_haversine_km(latitude, longitude,
                                                 latitude_sli, longitude_sli))
  joined <- joined[
    order(joined$.opcc_row, joined$distance_km),
    ,
    drop = FALSE
  ]
  joined <- joined[!duplicated(joined$.opcc_row), , drop = FALSE]
  joined <- joined[order(joined$.opcc_row), , drop = FALSE]
  joined$.opcc_row <- NULL
  rownames(joined) <- NULL
  joined
}

sli_compute_metrics <- function(centroids, sli) {
  joined <- sli_compute_point_distances(centroids, sli)

  overall <- joined |>
    dplyr::summarise(
      n                     = dplyr::n(),
      median_distance_km    = stats::median(distance_km, na.rm = TRUE),
      mean_distance_km      = base::mean(distance_km, na.rm = TRUE),
      p90_distance_km       = stats::quantile(distance_km, 0.90, na.rm = TRUE),
      p95_distance_km       = stats::quantile(distance_km, 0.95, na.rm = TRUE),
      p99_distance_km       = stats::quantile(distance_km, 0.99, na.rm = TRUE),
      max_distance_km       = base::max(distance_km, na.rm = TRUE)
    )

  by_source <- joined |>
    dplyr::group_by(point_source) |>
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

.sli_ratio <- function(numerator, denominator) {
  if (denominator == 0L) {
    return(NA_real_)
  }
  as.numeric(numerator) / as.numeric(denominator)
}

.sli_validate_postal_codes <- function(x) {
  postal_code_pattern <- paste0(
    "^[ABCEGHJ-NPRSTVXY][0-9][ABCEGHJ-NPRSTVWXYZ] ",
    "[0-9][ABCEGHJ-NPRSTVWXYZ][0-9]$"
  )
  valid <- grepl(
    postal_code_pattern,
    x
  )
  if (anyNA(x) || any(!valid)) {
    stop("postal_code contains missing or invalid Canadian postal codes")
  }
}

sli_validate_output_directory <- function(
    output_dir,
    repo_root,
    synthetic) {
  valid_path <- function(x) {
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  }
  if (!valid_path(output_dir) || !valid_path(repo_root)) {
    stop("output_dir and repo_root must be non-empty paths")
  }
  if (!is.logical(synthetic) || length(synthetic) != 1L ||
      is.na(synthetic)) {
    stop("synthetic must be TRUE or FALSE")
  }
  if (synthetic) {
    return(invisible(TRUE))
  }

  output_dir <- path.expand(output_dir)
  if (file.exists(output_dir) && !dir.exists(output_dir)) {
    stop("Licensed validation output must be a directory")
  }
  if (dir.exists(output_dir)) {
    output_path <- normalizePath(output_dir, mustWork = TRUE)
  } else {
    output_parent <- dirname(output_dir)
    if (!dir.exists(output_parent)) {
      stop("Licensed validation output parent directory must exist")
    }
    output_path <- file.path(
      normalizePath(output_parent, mustWork = TRUE),
      basename(output_dir)
    )
  }
  repository_path <- normalizePath(repo_root, mustWork = TRUE)
  repository_prefix <- paste0(repository_path, .Platform$file.sep)
  inside_repository <- identical(output_path, repository_path) ||
    startsWith(output_path, repository_prefix)
  if (inside_repository) {
    stop("Licensed validation output must be outside the repository")
  }

  invisible(TRUE)
}

# Normalize an OPCC or licensed-reference link table without collapsing
# distinct geographies for the same postal code.
sli_normalize_link_table <- function(
    x,
    level = c("DB", "DA"),
    role = c("opcc", "reference")) {
  level <- match.arg(level)
  role <- match.arg(role)
  if (!is.data.frame(x)) {
    stop("link input must be a data frame")
  }

  id_column <- if (level == "DB") "DBUID" else "DAUID"
  required <- c("postal_code", id_column)
  missing <- setdiff(required, names(x))
  if (length(missing) > 0L) {
    stop("link input is missing: ", paste(missing, collapse = ", "))
  }
  if (!is.character(x[[id_column]])) {
    stop(id_column, " must be character to preserve identifier precision")
  }

  postal_code <- sli_normalize_postal_code(x$postal_code)
  geo_id <- trimws(x[[id_column]])
  .sli_validate_postal_codes(postal_code)

  id_pattern <- if (level == "DB") "^35[0-9]{9}$" else "^35[0-9]{6}$"
  if (anyNA(geo_id) || any(!grepl(id_pattern, geo_id))) {
    stop(id_column, " must contain Ontario ", level, " identifiers")
  }

  if (role == "opcc") {
    if (!"best_link" %in% names(x) ||
        !is.logical(x$best_link) ||
        anyNA(x$best_link)) {
      stop("OPCC links require non-missing logical best_link values")
    }
    best_link <- x$best_link
  } else {
    best_link <- rep(NA, length(postal_code))
  }

  out <- data.frame(
    postal_code = postal_code,
    geo_id = geo_id,
    best_link = best_link,
    stringsAsFactors = FALSE
  )
  duplicate_pair <- duplicated(out[c("postal_code", "geo_id")])
  if (role == "opcc" && any(duplicate_pair)) {
    stop("OPCC links contain duplicate postal-code/geography pairs")
  }
  if (role == "reference") {
    out <- out[!duplicate_pair, , drop = FALSE]
  }

  if (role == "opcc") {
    best_count <- tapply(out$best_link, out$postal_code, sum)
    if (any(best_count != 1L)) {
      stop("Each OPCC postal code must have exactly one best_link")
    }
  }

  out[order(out$postal_code, out$geo_id), , drop = FALSE]
}

.sli_link_summary <- function(per_code) {
  n_codes <- nrow(per_code)
  opcc_links <- sum(per_code$opcc_links)
  reference_links <- sum(per_code$reference_links)
  matched_links <- sum(per_code$matched_links)
  missing_links <- sum(per_code$missing_links)
  excess_links <- sum(per_code$excess_links)
  pair_precision <- .sli_ratio(matched_links, opcc_links)
  pair_recall <- .sli_ratio(matched_links, reference_links)
  f1_denominator <- pair_precision + pair_recall

  list(
    n_codes = n_codes,
    opcc_links = opcc_links,
    reference_links = reference_links,
    matched_links = matched_links,
    missing_links = missing_links,
    excess_links = excess_links,
    pair_precision = pair_precision,
    pair_recall = pair_recall,
    f1 = if (is.na(f1_denominator)) {
      NA_real_
    } else if (f1_denominator == 0) {
      0
    } else {
      2 * pair_precision * pair_recall / f1_denominator
    },
    micro_jaccard = .sli_ratio(
      matched_links,
      matched_links + missing_links + excess_links
    ),
    macro_jaccard = if (n_codes == 0L) {
      NA_real_
    } else {
      mean(per_code$jaccard)
    },
    any_link_codes = sum(per_code$any_link),
    any_link_rate = .sli_ratio(sum(per_code$any_link), n_codes),
    exact_set_codes = sum(per_code$exact_set),
    exact_set_rate = .sli_ratio(sum(per_code$exact_set), n_codes),
    opcc_best_in_reference_codes = sum(per_code$best_in_reference),
    opcc_best_in_reference_rate = .sli_ratio(
      sum(per_code$best_in_reference),
      n_codes
    )
  )
}

# Compare OPCC and reference geography sets using aggregate-only metrics.
sli_compute_link_metrics <- function(
    opcc,
    reference,
    level = c("DB", "DA")) {
  level <- match.arg(level)
  opcc <- sli_normalize_link_table(opcc, level, "opcc")
  reference <- sli_normalize_link_table(reference, level, "reference")

  opcc_codes <- unique(opcc$postal_code)
  reference_codes <- unique(reference$postal_code)
  compared_codes <- intersect(opcc_codes, reference_codes)

  coverage <- list(
    opcc_codes = length(opcc_codes),
    reference_codes = length(reference_codes),
    compared_codes = length(compared_codes),
    opcc_only_codes = length(setdiff(opcc_codes, reference_codes)),
    reference_only_codes = length(setdiff(reference_codes, opcc_codes)),
    reference_coverage = .sli_ratio(
      length(compared_codes),
      length(reference_codes)
    ),
    opcc_benchmark_coverage = .sli_ratio(
      length(compared_codes),
      length(opcc_codes)
    )
  )

  per_code <- if (length(compared_codes) == 0L) {
    data.frame(
      opcc_links = integer(),
      reference_links = integer(),
      matched_links = integer(),
      missing_links = integer(),
      excess_links = integer(),
      jaccard = numeric(),
      any_link = logical(),
      exact_set = logical(),
      best_in_reference = logical(),
      reference_cardinality = character()
    )
  } else {
    separator <- "\034"
    opcc_pair <- paste(opcc$postal_code, opcc$geo_id, sep = separator)
    reference_pair <- paste(
      reference$postal_code,
      reference$geo_id,
      sep = separator
    )
    opcc_count_table <- table(opcc$postal_code)
    reference_count_table <- table(reference$postal_code)
    matched_table <- table(
      opcc$postal_code[opcc_pair %in% reference_pair]
    )
    best_pair <- opcc_pair[opcc$best_link]
    names(best_pair) <- opcc$postal_code[opcc$best_link]

    matched_links <- as.integer(matched_table[compared_codes])
    matched_links[is.na(matched_links)] <- 0L
    opcc_links <- as.integer(opcc_count_table[compared_codes])
    reference_links <- as.integer(reference_count_table[compared_codes])
    missing_links <- reference_links - matched_links
    excess_links <- opcc_links - matched_links
    union_links <- matched_links + missing_links + excess_links
    best_in_reference <- unname(best_pair[compared_codes]) %in% reference_pair

    data.frame(
      opcc_links = opcc_links,
      reference_links = reference_links,
      matched_links = matched_links,
      missing_links = missing_links,
      excess_links = excess_links,
      jaccard = matched_links / union_links,
      any_link = matched_links > 0L,
      exact_set = missing_links == 0L & excess_links == 0L,
      best_in_reference = best_in_reference,
      reference_cardinality = ifelse(
        reference_links == 1L,
        "single",
        "multiple"
      ),
      stringsAsFactors = FALSE
    )
  }

  link_accuracy <- .sli_link_summary(per_code)
  strata <- lapply(c("single", "multiple"), function(cardinality) {
    stratum <- per_code[
      per_code$reference_cardinality == cardinality,
      ,
      drop = FALSE
    ]
    c(
      list(reference_cardinality = cardinality),
      .sli_link_summary(stratum)
    )
  })
  by_reference_cardinality <- do.call(
    rbind.data.frame,
    c(strata, stringsAsFactors = FALSE)
  )

  list(
    level = level,
    coverage = coverage,
    link_accuracy = link_accuracy,
    by_reference_cardinality = by_reference_cardinality
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

# Resolve and validate that a producer revision exists and contains every named
# generator script. Returns the full 40-character SHA.
sli_validate_producer_ref <- function(producer_ref, scripts) {
  if (is.null(producer_ref) || !nzchar(producer_ref)) {
    stop("--producer-ref is required.")
  }

  # Resolve to full SHA
  full_sha <- tryCatch(
    suppressWarnings(
      system2("git", c("rev-parse", producer_ref),
              stdout = TRUE, stderr = TRUE)
    ),
    error = function(e) e
  )

  if (inherits(full_sha, "error") || !is.null(attr(full_sha, "status")) ||
      length(full_sha) == 0 || !grepl("^[0-9a-f]{40}$", full_sha[1])) {
    stop("Producer revision not found or invalid: ", producer_ref)
  }

  full_sha <- full_sha[1]

  # Validate that the resolved SHA contains all named scripts
  for (s in scripts) {
    res <- tryCatch(
      suppressWarnings(
        system2("git", c("cat-file", "-e", paste0(full_sha, ":", s)),
                stdout = TRUE, stderr = TRUE)
      ),
      error = function(e) e
    )
    if (inherits(res, "error") || !is.null(attr(res, "status"))) {
      stop("Producer revision ", full_sha,
           " does not contain script: ", s)
    }
  }

  full_sha
}
