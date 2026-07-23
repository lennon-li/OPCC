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

.sli_find_column <- function(names_lower, candidates) {
  position <- match(candidates, names_lower, nomatch = 0L)
  position <- position[position > 0L]
  if (length(position) == 0L) {
    return(NA_integer_)
  }
  position[1]
}

# Read an Ontario PCCF-shaped extract without collapsing distinct point or
# geography observations. The caller is responsible for licensed access.
sli_read_pccf_reference <- function(path, contract = NULL) {
  if (!file.exists(path)) {
    stop("Licensed PCCF input is not available")
  }
  raw <- tryCatch(
    readr::read_csv(
      path,
      col_types = readr::cols(.default = readr::col_character()),
      show_col_types = FALSE
    ),
    error = function(error) {
      stop("Licensed PCCF input could not be read", call. = FALSE)
    }
  )
  names_lower <- tolower(names(raw))
  if (is.null(contract)) {
    candidates <- list(
      postal_code = c(
        "postal_code", "postalcode", "pc", "mail_postal_code", "postal_cd"
      ),
      latitude = c("latitude", "lat"),
      longitude = c("longitude", "lon", "long"),
      DBUID = c("dbuid", "db"),
      DAUID = c("dauid", "da")
    )
    positions <- vapply(
      candidates,
      function(candidate) .sli_find_column(names_lower, candidate),
      integer(1)
    )
  } else {
    contract <- sli_validate_pccf_contract(contract)
    mapped_names <- unlist(contract$columns, use.names = TRUE)
    positions <- match(mapped_names, names(raw))
    names(positions) <- names(mapped_names)
  }
  if (anyNA(positions)) {
    missing <- names(positions)[is.na(positions)]
    stop(
      "PCCF reference is missing required columns: ",
      paste(missing, collapse = ", ")
    )
  }

  reference <- data.frame(
    postal_code = sli_normalize_postal_code(raw[[positions["postal_code"]]]),
    latitude = suppressWarnings(
      as.numeric(raw[[positions["latitude"]]])
    ),
    longitude = suppressWarnings(
      as.numeric(raw[[positions["longitude"]]])
    ),
    DBUID = trimws(raw[[positions["DBUID"]]]),
    DAUID = trimws(raw[[positions["DAUID"]]]),
    stringsAsFactors = FALSE
  )
  if (nrow(reference) == 0L) {
    stop("PCCF reference contains no rows")
  }
  .sli_validate_postal_codes(reference$postal_code)
  if (anyNA(reference$latitude) || anyNA(reference$longitude) ||
      any(reference$latitude < 41 | reference$latitude > 57.5) ||
      any(reference$longitude < -96 | reference$longitude > -73.5)) {
    stop("PCCF reference coordinates must be within Ontario coordinate bounds")
  }
  if (anyNA(reference$DBUID) ||
      any(!grepl("^35[0-9]{9}$", reference$DBUID))) {
    stop("PCCF DBUID values must be 11-character Ontario identifiers")
  }
  if (anyNA(reference$DAUID) ||
      any(!grepl("^35[0-9]{6}$", reference$DAUID))) {
    stop("PCCF DAUID values must be 8-character Ontario identifiers")
  }
  if (any(substr(reference$DBUID, 1L, 8L) != reference$DAUID)) {
    stop("PCCF DBUID and DAUID values are inconsistent")
  }

  list(
    row_count = nrow(reference),
    exact_duplicate_rows = nrow(reference) - nrow(unique(reference)),
    points = unique(reference[c(
      "postal_code", "latitude", "longitude"
    )]),
    db_links = unique(reference[c("postal_code", "DBUID")]),
    da_links = unique(reference[c("postal_code", "DAUID")])
  )
}

sli_validate_pccf_identity <- function(label, vintage) {
  scalar_string <- function(x) {
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
  }
  if (!scalar_string(label) || nchar(label) > 100L ||
      grepl("[/\\\\]", label)) {
    stop("PCCF label must be a short description, not a path")
  }
  if (!scalar_string(vintage) ||
      !grepl("^[0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?$", vintage)) {
    stop("PCCF vintage must use YYYY, YYYY-MM, or YYYY-MM-DD")
  }
  list(label = trimws(label), vintage = vintage)
}

sli_parse_pccf_args <- function(args) {
  output <- list(
    m1_release_dir = NULL,
    m2_release_id = NULL,
    m5_release_id = NULL,
    pccf_csv = NULL,
    pccf_contract = NULL,
    output_dir = NULL,
    producer_ref = NULL
  )
  names_by_flag <- stats::setNames(
    names(output),
    paste0("--", gsub("_", "-", names(output)))
  )
  index <- 1L
  while (index <= length(args)) {
    flag <- args[index]
    field <- unname(names_by_flag[flag])
    if (length(field) == 0L || is.na(field)) {
      stop("Unknown argument: ", flag)
    }
    if (index == length(args)) {
      stop("Missing value for ", flag)
    }
    output[[field]] <- args[index + 1L]
    index <- index + 2L
  }
  missing <- names(output)[vapply(output, is.null, logical(1))]
  if (length(missing) > 0L) {
    stop(
      "Missing required arguments: ",
      paste(paste0("--", gsub("_", "-", missing)), collapse = ", ")
    )
  }
  output
}

sli_validate_pccf_contract <- function(contract) {
  required <- c(
    "schema_version", "product", "product_vintage", "census_vintage",
    "province_uid", "coordinate_crs", "point_semantics", "columns",
    "missing_value_policy", "duplicate_row_policy"
  )
  if (!is.list(contract) ||
      !all(required %in% names(contract))) {
    stop("PCCF contract is missing required fields")
  }
  if (!identical(as.integer(contract$schema_version), 1L) ||
      !identical(contract$product, "PCCF") ||
      !identical(contract$census_vintage, "2021") ||
      !identical(contract$province_uid, "35") ||
      !identical(contract$coordinate_crs, "EPSG:4326") ||
      !identical(
        contract$point_semantics,
        "pccf_representative_point"
      ) ||
      !identical(contract$missing_value_policy, "error") ||
      !identical(
        contract$duplicate_row_policy,
        "count_then_deduplicate_exact"
      )) {
    stop("PCCF contract must declare Ontario 2021 data in EPSG:4326")
  }
  sli_validate_pccf_identity("PCCF", contract$product_vintage)
  required_columns <- c(
    "postal_code", "latitude", "longitude", "DBUID", "DAUID"
  )
  if (!is.list(contract$columns) ||
      !identical(names(contract$columns), required_columns)) {
    stop("PCCF contract columns must map the required canonical fields")
  }
  mapped <- unlist(contract$columns, use.names = FALSE)
  if (anyNA(mapped) || any(!nzchar(mapped)) ||
      anyDuplicated(mapped) > 0L) {
    stop("PCCF contract column mappings must be non-empty and unique")
  }
  contract
}

sli_validate_private_input <- function(path, repo_root) {
  if (!is.character(path) || length(path) != 1L ||
      is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("Licensed PCCF input must be an existing file")
  }
  input_path <- normalizePath(path, mustWork = TRUE)
  repository_path <- normalizePath(repo_root, mustWork = TRUE)
  repository_prefix <- paste0(repository_path, .Platform$file.sep)
  if (identical(input_path, repository_path) ||
      startsWith(input_path, repository_prefix)) {
    stop("Licensed PCCF input must be outside the repository")
  }
  invisible(TRUE)
}

sli_digest_private_file <- function(path) {
  tryCatch(
    digest::digest(path, "sha256", file = TRUE),
    error = function(error) {
      stop("Licensed PCCF input could not be hashed", call. = FALSE)
    }
  )
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

  if (nrow(joined) == 0L) {
    reference_codes <- dplyr::n_distinct(sli$postal_code)
    empty_stat <- list(
      n = 0L,
      median_distance_km = NA_real_,
      mean_distance_km = NA_real_,
      p90_distance_km = NA_real_,
      p95_distance_km = NA_real_,
      p99_distance_km = NA_real_,
      max_distance_km = NA_real_
    )
    empty_by_source <- data.frame(
      point_source = character(),
      n = integer(),
      median_distance_km = numeric(),
      mean_distance_km = numeric(),
      p90_distance_km = numeric(),
      p95_distance_km = numeric(),
      p99_distance_km = numeric(),
      max_distance_km = numeric()
    )
    return(list(
      overall = empty_stat,
      by_source = empty_by_source,
      coverage = list(
        distinct_open_postal_codes = dplyr::n_distinct(
          centroids$postal_code
        ),
        distinct_sli_postal_codes = reference_codes,
        matched_postal_codes = 0L,
        coverage_pct = if (reference_codes == 0L) NA_real_ else 0
      ),
      joined_n = 0L
    ))
  }

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

# Verify a released M2 or M5 correspondence artifact and return character-safe
# link fields for validation.
sli_verify_link_artifact <- function(
    gz_path,
    manifest,
    level = c("DB", "DA")) {
  level <- match.arg(level)
  if (!file.exists(gz_path)) {
    stop(level, " artifact not found: ", gz_path)
  }
  artifact <- manifest$release_artifact
  if (is.null(artifact$sha256) ||
      is.null(artifact$uncompressed_sha256)) {
    stop(level, " manifest is missing release artifact hashes")
  }
  if (!is.null(artifact$path) &&
      !identical(basename(gz_path), basename(artifact$path))) {
    stop(level, " artifact basename does not match its manifest")
  }
  if (!is.null(artifact$bytes) &&
      !identical(as.numeric(file.info(gz_path)$size),
                 as.numeric(artifact$bytes))) {
    stop(level, " artifact byte size does not match its manifest")
  }

  gz_bytes <- readBin(gz_path, raw(), n = file.info(gz_path)$size)
  gz_sha256 <- digest::digest(gz_bytes, "sha256", serialize = FALSE)
  if (!identical(gz_sha256, artifact$sha256)) {
    stop(level, " gzip hash mismatch")
  }
  csv_bytes <- memDecompress(gz_bytes, type = "gzip")
  csv_sha256 <- digest::digest(csv_bytes, "sha256", serialize = FALSE)
  if (!identical(csv_sha256, artifact$uncompressed_sha256)) {
    stop(level, " decompressed CSV hash mismatch")
  }

  connection <- rawConnection(csv_bytes, "r")
  on.exit(try(close(connection), silent = TRUE), add = TRUE)
  result <- readr::read_csv(
    connection,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  id_column <- if (level == "DB") "DBUID" else "DAUID"
  required <- c("postal_code", id_column, "best_link")
  missing <- setdiff(required, names(result))
  if (length(missing) > 0L) {
    stop(level, " artifact is missing: ", paste(missing, collapse = ", "))
  }
  expected_rows <- manifest$row_counts$correspondence_rows
  if (is.null(expected_rows) || nrow(result) != expected_rows) {
    stop(level, " artifact row count does not match its manifest")
  }
  best_link <- tolower(trimws(result$best_link))
  if (any(!best_link %in% c("true", "false"))) {
    stop(level, " artifact has invalid best_link values")
  }
  result$best_link <- best_link == "true"
  result
}

.sli_sanitize_point_metrics <- function(metrics) {
  list(
    overall = metrics$overall,
    by_source = as.data.frame(metrics$by_source),
    coverage = list(
      opcc_codes = metrics$coverage$distinct_open_postal_codes,
      reference_codes = metrics$coverage$distinct_sli_postal_codes,
      compared_codes = metrics$coverage$matched_postal_codes,
      reference_coverage = metrics$coverage$coverage_pct / 100
    ),
    comparisons = metrics$joined_n
  )
}

sli_compute_pccf_metrics <- function(
    centroids,
    opcc_db,
    opcc_da,
    reference) {
  required <- c("points", "db_links", "da_links")
  if (!is.list(reference) ||
      !all(required %in% names(reference))) {
    stop("reference must contain points, db_links, and da_links")
  }
  point_metrics <- sli_compute_metrics(centroids, reference$points)
  db_metrics <- sli_compute_link_metrics(
    opcc_db,
    reference$db_links,
    level = "DB"
  )
  da_metrics <- sli_compute_link_metrics(
    opcc_da,
    reference$da_links,
    level = "DA"
  )
  if (point_metrics$joined_n == 0L ||
      db_metrics$coverage$compared_codes == 0L ||
      da_metrics$coverage$compared_codes == 0L) {
    stop("PCCF reference has no comparable rows for one or more milestones")
  }

  result <- list(
    point_accuracy = .sli_sanitize_point_metrics(point_metrics),
    db_accuracy = db_metrics,
    da_accuracy = da_metrics
  )
  sli_validate_aggregate_output(result)
  result
}

sli_validate_aggregate_output <- function(x) {
  restricted_names <- c(
    "postal_code", "dbuid", "dauid", "latitude", "longitude",
    "lat", "lon", "path", "file"
  )
  inspect <- function(value) {
    value_names <- names(value)
    if (!is.null(value_names) &&
        any(tolower(value_names) %in% restricted_names)) {
      stop("Aggregate output contains a restricted field")
    }
    if (is.list(value)) {
      invisible(lapply(value, inspect))
    } else if (is.character(value)) {
      if (any(grepl("[/\\\\]", value))) {
        stop("Aggregate output contains a path-like value")
      }
      postal_pattern <- paste0(
        "^[ABCEGHJ-NPRSTVXY][0-9][ABCEGHJ-NPRSTVWXYZ] ?",
        "[0-9][ABCEGHJ-NPRSTVWXYZ][0-9]$"
      )
      if (any(grepl(postal_pattern, value)) ||
          any(grepl("^35[0-9]{6}([0-9]{3})?$", value))) {
        stop("Aggregate output contains a restricted value")
      }
    }
    invisible(TRUE)
  }
  inspect(x)
  invisible(TRUE)
}

sli_pccf_report_lines <- function(result) {
  point <- result$metrics$point_accuracy
  db <- result$metrics$db_accuracy
  da <- result$metrics$da_accuracy
  c(
    "# OPCC Private PCCF Validation",
    "",
    paste("Mode:", result$mode),
    paste("Reference product:", result$pccf$product),
    paste("PCCF vintage:", result$pccf$product_vintage),
    paste("PCCF rows:", format(result$pccf$raw_rows, big.mark = ",")),
    "",
    "This report contains aggregate QA results only. The licensed PCCF",
    "extract remains local and is not copied, cached, or redistributed.",
    "",
    "## M1 point comparison",
    "",
    sprintf(
      "- Comparable postal codes: %s of %s reference codes (%.2f%%)",
      format(point$coverage$compared_codes, big.mark = ","),
      format(point$coverage$reference_codes, big.mark = ","),
      100 * point$coverage$reference_coverage
    ),
    sprintf("- Median nearest-point distance: %.3f km",
            point$overall$median_distance_km),
    sprintf("- 95th percentile nearest-point distance: %.3f km",
            point$overall$p95_distance_km),
    "",
    "## M2 dissemination-block comparison",
    "",
    sprintf("- Comparable postal codes: %s",
            format(db$coverage$compared_codes, big.mark = ",")),
    sprintf("- Any-link agreement: %.2f%%",
            100 * db$link_accuracy$any_link_rate),
    sprintf("- Exact-set agreement: %.2f%%",
            100 * db$link_accuracy$exact_set_rate),
    sprintf("- OPCC best link contained in PCCF set: %.2f%%",
            100 * db$link_accuracy$opcc_best_in_reference_rate),
    "",
    "## M5 dissemination-area comparison",
    "",
    sprintf("- Comparable postal codes: %s",
            format(da$coverage$compared_codes, big.mark = ",")),
    sprintf("- Any-link agreement: %.2f%%",
            100 * da$link_accuracy$any_link_rate),
    sprintf("- Exact-set agreement: %.2f%%",
            100 * da$link_accuracy$exact_set_rate),
    sprintf("- OPCC best link contained in PCCF set: %.2f%%",
            100 * da$link_accuracy$opcc_best_in_reference_rate),
    "",
    "These results are private diagnostic evidence. Public publication",
    "requires a separate allowlisted and disclosure-reviewed attestation."
  )
}

sli_write_pccf_outputs <- function(result, output_dir) {
  sli_validate_aggregate_output(result)
  if (dir.exists(output_dir) || file.exists(output_dir)) {
    stop("Private validation output directory must not already exist")
  }
  created <- tryCatch(
    suppressWarnings(dir.create(
      output_dir,
      recursive = FALSE,
      mode = "0700"
    )),
    error = function(error) FALSE
  )
  if (!isTRUE(created) || !dir.exists(output_dir)) {
    stop("Private validation output directory could not be created")
  }
  suppressWarnings(Sys.chmod(output_dir, mode = "0700"))

  final_names <- c(
    "pccf_validation_metrics.json",
    "pccf_validation_report.md",
    "pccf_validation_manifest.json"
  )
  final_paths <- file.path(output_dir, final_names)
  temporary_paths <- paste0(final_paths, ".tmp")
  complete <- FALSE
  on.exit({
    if (!complete) {
      unlink(c(temporary_paths, final_paths), force = TRUE)
    }
  }, add = TRUE)

  output_manifest <- tryCatch({
    jsonlite::write_json(
      result,
      temporary_paths[1],
      pretty = TRUE,
      auto_unbox = TRUE,
      na = "null"
    )
    writeLines(
      sli_pccf_report_lines(result),
      temporary_paths[2],
      useBytes = TRUE
    )
    manifest <- list(
      schema_version = 1L,
      mode = result$mode,
      build_ref = result$build_ref,
      pccf = result$pccf,
      releases = result$releases,
      release_index_sha256 = result$release_index_sha256,
      outputs = list(
        metrics_sha256 = digest::digest(
          temporary_paths[1],
          "sha256",
          file = TRUE
        ),
        report_sha256 = digest::digest(
          temporary_paths[2],
          "sha256",
          file = TRUE
        )
      )
    )
    sli_validate_aggregate_output(manifest)
    jsonlite::write_json(
      manifest,
      temporary_paths[3],
      pretty = TRUE,
      auto_unbox = TRUE,
      na = "null"
    )
    manifest
  }, error = function(error) {
    stop("Private validation outputs could not be written", call. = FALSE)
  })
  renamed <- vapply(
    seq_along(final_paths),
    function(index) {
      file.rename(temporary_paths[index], final_paths[index])
    },
    logical(1)
  )
  if (!all(renamed)) {
    stop("Private validation outputs could not be finalised")
  }
  complete <- TRUE
  invisible(output_manifest)
}

sli_build_release_binding <- function(
    manifest,
    manifest_path,
    artifact_path,
    milestone = c("M1", "M2", "M5"),
    release_id = NULL) {
  milestone <- match.arg(milestone)
  if (!file.exists(manifest_path) || !file.exists(artifact_path)) {
    stop(milestone, " release binding inputs do not exist")
  }
  if (milestone == "M1") {
    vintage <- manifest$release_date
    census_vintage <- NULL
    artifact_sha256 <- manifest$artifact$gz_sha256
    rows <- manifest$artifact$total_rows
  } else if (milestone == "M2") {
    vintage <- manifest$source_vintage
    census_vintage <- manifest$census_vintage
    artifact_sha256 <- manifest$release_artifact$sha256
    rows <- manifest$row_counts$correspondence_rows
  } else {
    vintage <- manifest$source_m2$vintage
    census_vintage <- manifest$source_m2$census_vintage
    artifact_sha256 <- manifest$release_artifact$sha256
    rows <- manifest$row_counts$correspondence_rows
  }
  scalar <- function(x) {
    !is.null(x) && length(x) == 1L && !is.na(x)
  }
  valid_vintage <- scalar(vintage) ||
    (is.list(vintage) &&
       length(vintage) > 0L &&
       all(vapply(vintage, scalar, logical(1))))
  if (!valid_vintage || !scalar(artifact_sha256) || !scalar(rows)) {
    stop(milestone, " manifest lacks required release metadata")
  }
  actual_artifact_sha256 <- digest::digest(
    artifact_path,
    "sha256",
    file = TRUE
  )
  if (!identical(actual_artifact_sha256, artifact_sha256)) {
    stop(milestone, " release binding artifact hash mismatch")
  }

  binding <- list(
    milestone = milestone,
    release_id = release_id,
    vintage = vintage,
    census_vintage = census_vintage,
    manifest_sha256 = digest::digest(
      manifest_path,
      "sha256",
      file = TRUE
    ),
    artifact_sha256 = actual_artifact_sha256,
    rows = as.integer(rows)
  )
  sli_validate_aggregate_output(binding)
  binding
}

sli_verify_indexed_release <- function(
    index,
    milestone = c("m2", "m5"),
    release_id,
    artifact_path,
    manifest_path) {
  milestone <- match.arg(milestone)
  spec <- index[[milestone]][[release_id]]
  if (is.null(spec) ||
      is.null(spec$sha256) ||
      is.null(spec$manifest_sha256)) {
    stop("Release is not checksum-pinned in the release index")
  }
  artifact_sha <- digest::digest(artifact_path, "sha256", file = TRUE)
  manifest_sha <- digest::digest(manifest_path, "sha256", file = TRUE)
  if (!identical(artifact_sha, spec$sha256) ||
      !identical(manifest_sha, spec$manifest_sha256)) {
    stop("Indexed release checksum mismatch")
  }
  invisible(TRUE)
}

sli_validate_release_lineage <- function(
    m1_manifest,
    m2_manifest,
    m2_artifact_path,
    m2_manifest_path,
    m5_manifest,
    pccf_census_vintage) {
  m2_artifact_sha <- digest::digest(
    m2_artifact_path,
    "sha256",
    file = TRUE
  )
  m2_manifest_sha <- digest::digest(
    m2_manifest_path,
    "sha256",
    file = TRUE
  )
  if (!identical(
        m5_manifest$source_m2$artifact_sha256,
        m2_artifact_sha
      ) ||
      !identical(
        m5_manifest$source_m2$manifest_sha256,
        m2_manifest_sha
      )) {
    stop("M5 parent does not match the selected M2 release")
  }
  census_vintages <- list(
    m2_manifest$census_vintage,
    m5_manifest$source_m2$census_vintage,
    pccf_census_vintage
  )
  valid_census <- vapply(
    census_vintages,
    function(value) {
      is.character(value) &&
        length(value) == 1L &&
        !is.na(value) &&
        nzchar(value)
    },
    logical(1)
  )
  if (!all(valid_census) ||
      length(unique(unlist(census_vintages))) != 1L) {
    stop("M2, M5, and PCCF census vintages do not match")
  }
  m2_nar_vintage <- if (is.list(m2_manifest$source_vintage)) {
    m2_manifest$source_vintage$nar
  } else {
    m2_manifest$source_vintage
  }
  if (!identical(
        m1_manifest$sources$nar$release_date,
        m2_nar_vintage
      )) {
    stop("M1 and M2 NAR source vintages do not match")
  }
  invisible(TRUE)
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
