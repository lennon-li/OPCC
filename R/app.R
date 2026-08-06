#' Launch the OPCC Shiny app
#'
#' Launches a Shiny app that joins a user-uploaded CSV to the OPCC
#' postal-code-to-DA correspondence: pick the postal-code column (an
#' auto-detected candidate is preselected), click Join to see the result
#' table, and draw the matched dissemination areas on a map. The joined
#' CSV, the map as HTML, and an R script reproducing both artifacts are
#' downloadable.
#'
#' @param ... Passed to [shiny::runApp()].
#'
#' @return Called for its side effect (launches the Shiny app). Invisibly
#'   returns `NULL`.
#'
#' @examples
#' if (interactive()) {
#'   run_app()
#' }
#'
#' @export
run_app <- function(...) {
  rlang::check_installed(
    c("shiny", "bslib (>= 0.6.0)", "DT", "leaflet", "htmlwidgets",
      "promises", "future", "sf"),
    reason = "to run the OPCC Shiny app."
  )
  if (utils::packageVersion("shiny") < "1.8.0") {
    stop("The OPCC Shiny app requires shiny >= 1.8.0; installed: ",
         utils::packageVersion("shiny"), call. = FALSE)
  }
  app_dir <- system.file("shiny", package = "OPCC")
  if (!nzchar(app_dir)) {
    stop("Could not find the OPCC Shiny app directory. Try re-installing the package.", call. = FALSE)
  }
  shiny::runApp(app_dir, ...)
}

.detect_postal_column <- function(records) {
  if (nrow(records) == 0L || ncol(records) == 0L) {
    return(NA_character_)
  }
  cleaned <- tolower(gsub("[^a-z0-9]+", "", names(records)))
  name_hits <- which(grepl("postal|pcode|postcode|zipcode|^zip$", cleaned))
  if (length(name_hits) > 0L) {
    return(names(records)[[name_hits[[1]]]])
  }
  scores <- vapply(records, function(column) {
    values <- as.character(column)
    values <- values[!is.na(values) & nzchar(trimws(values))]
    if (length(values) == 0L) {
      return(0)
    }
    mean(!is.na(normalize_postal_code(values)))
  }, numeric(1))
  if (any(scores >= 0.5)) {
    return(names(records)[[which.max(scores)]])
  }
  NA_character_
}

.parse_postal_text <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) {
    return(character())
  }
  parts <- unlist(strsplit(text, "[\r\n]+"))
  parts <- trimws(parts)
  parts[nzchar(parts)]
}

.postal_da_join <- function(records, postal_col, correspondence, all_links = FALSE) {
  if (!postal_col %in% names(records)) {
    stop(sprintf("Unknown postal code column: %s", postal_col), call. = FALSE)
  }
  required <- c("postal_code", "DAUID", "best_link")
  if (!all(required %in% names(correspondence))) {
    stop("Correspondence is missing postal_code, DAUID, or best_link", call. = FALSE)
  }
  raw_chr <- as.character(records[[postal_col]])
  keys <- normalize_postal_code(raw_chr)
  invalid <- is.na(keys) & !is.na(raw_chr) & nzchar(trimws(raw_chr))
  codes <- unique(keys[!is.na(keys)])
  links <- correspondence[correspondence$postal_code %in% codes, , drop = FALSE]
  if (!all_links) {
    links <- links[links$best_link, , drop = FALSE]
  }
  # Expand links by source row instead of using merge(), which does not retain
  # interleaved left-hand order. Correspondence order is the stable tie-breaker
  # for multiple links belonging to one source record.
  link_rows <- split(seq_len(nrow(links)), links$postal_code)
  matched <- lapply(keys, function(key) {
    rows <- if (is.na(key)) NULL else link_rows[[key]]
    if (is.null(rows) || length(rows) == 0L) NA_integer_ else rows
  })
  source_rows <- rep(seq_len(nrow(records)), lengths(matched))
  link_index <- unlist(matched, use.names = FALSE)
  joined <- records[source_rows, , drop = FALSE]
  rownames(joined) <- NULL
  output_name <- "opcc_postal_code"
  if (output_name %in% names(joined)) {
    output_name <- ".opcc_join_postal_code"
    while (output_name %in% names(joined)) {
      output_name <- paste0(output_name, "_")
    }
  }
  joined[[output_name]] <- keys[source_rows]
  link_values <- links[link_index, setdiff(names(links), "postal_code"), drop = FALSE]
  link_source_names <- names(link_values)
  link_names <- link_source_names
  for (i in seq_along(link_names)) {
    while (link_names[[i]] %in% c(names(joined), link_names[seq_len(i - 1L)])) {
      link_names[[i]] <- paste0("opcc_", link_names[[i]])
    }
  }
  names(link_values) <- link_names
  rownames(link_values) <- NULL
  joined <- cbind(joined, link_values)
  attr(joined, "opcc_postal_code_col") <- output_name
  da_name <- link_names[match("DAUID", link_source_names)]
  attr(joined, "opcc_dauid_col") <- da_name
  list(
    joined = joined,
    postal_code_col = output_name,
    dauid_col = da_name,
    unmatched = setdiff(codes, unique(links$postal_code)),
    invalid_count = sum(invalid),
    n_input = nrow(records),
    n_codes = length(codes)
  )
}

.da_task_transition <- function(state, event, request = NULL) {
  if (identical(event, "invalidate")) {
    state$current_id <- NULL
    state$pending <- NULL
    return(state)
  }
  if (identical(event, "join")) {
    state$current_id <- request$id
    state$pending <- request
    if (is.null(state$running_id)) {
      state$running_id <- request$id
      state$pending <- NULL
      state$invoke <- request
    }
    return(state)
  }
  if (!identical(event, "finished")) {
    stop("Unknown DA task event", call. = FALSE)
  }
  state$accept <- identical(state$running_id, state$current_id)
  state$running_id <- NULL
  if (!is.null(state$pending)) {
    state$running_id <- state$pending$id
    state$invoke <- state$pending
    state$pending <- NULL
  }
  state
}

.deparse_chr <- function(x) {
  paste(deparse(x), collapse = "")
}

.render_opcc_reproducer_script <- function(input_file, postal_col, output_dir,
                                           vintage, all_links = FALSE,
                                           codes = NULL) {
  use_codes <- !is.null(codes)
  intro <- if (use_codes) {
    paste0(
      "# Reproduces opcc_postal_da.csv and opcc_map.html as produced by the\n",
      "# OPCC postal-code-to-dissemination-area Shiny app (OPCC::run_app()),\n",
      "# for postal codes typed directly into the app.\n",
      "#\n",
      "# Requires: OPCC, sf, leaflet, htmlwidgets.\n",
      "#   install.packages(c(\"sf\", \"leaflet\", \"htmlwidgets\"))\n",
      "#   install.packages(\"pak\"); pak::pak(\"lennon-li/OPCC\")\n",
      "\n",
      "library(OPCC)\n",
      "\n",
      "# Postal codes entered in the app, one per line.\n",
      "postal_codes <- ", .deparse_chr(codes), "\n",
      "postal_col <- ", .deparse_chr(postal_col), "\n",
      "output_dir <- ", .deparse_chr(output_dir), "\n",
      "vintage <- ", .deparse_chr(vintage), "\n",
      "all_links <- ", if (all_links) "TRUE" else "FALSE", "\n",
      "\n",
      "records <- data.frame(postal_code = postal_codes, ",
      "stringsAsFactors = FALSE)\n")
  } else {
    paste0(
      "# Reproduces opcc_postal_da.csv and opcc_map.html as produced by the\n",
      "# OPCC postal-code-to-dissemination-area Shiny app (OPCC::run_app()).\n",
      "#\n",
      "# Requires: OPCC, sf, leaflet, htmlwidgets.\n",
      "#   install.packages(c(\"sf\", \"leaflet\", \"htmlwidgets\"))\n",
      "#   install.packages(\"remotes\"); remotes::install_github(\"lennon-li/OPCC\")\n",
      "\n",
      "library(OPCC)\n",
      "\n",
      "# Point this at your own input file.\n",
      "input_file <- ", .deparse_chr(input_file), "\n",
      "postal_col <- ", .deparse_chr(postal_col), "\n",
      "output_dir <- ", .deparse_chr(output_dir), "\n",
      "vintage <- ", .deparse_chr(vintage), "\n",
      "all_links <- ", if (all_links) "TRUE" else "FALSE", "\n",
      "\n",
      "records <- utils::read.csv(input_file, stringsAsFactors = FALSE, ",
      "check.names = FALSE)\n")
  }
  paste0(
    intro,
    "# The correspondence reports codes normalized to \"A1A 1A1\", so the join\n",
    "# key must be normalized on this side too; joining on the column as typed\n",
    "# silently drops every code not already in that exact form. Ask for each\n",
    "# distinct code once, or duplicates on both sides multiply the rows.\n",
    "keys <- normalize_postal_code(records[[postal_col]])\n",
    "codes <- unique(keys[!is.na(keys)])\n",
    "\n",
    "correspondence <- get_da_correspondence(vintage = vintage)\n",
    "links <- correspondence[correspondence$postal_code %in% codes, , drop = FALSE]\n",
    "if (!all_links) links <- links[links$best_link, , drop = FALSE]\n",
    "# Retain input-row order; multiple links follow correspondence row order.\n",
    "link_rows <- split(seq_len(nrow(links)), links$postal_code)\n",
    "matched <- lapply(keys, function(key) {\n",
    "  rows <- if (is.na(key)) NULL else link_rows[[key]]\n",
    "  if (is.null(rows) || length(rows) == 0L) NA_integer_ else rows\n",
    "})\n",
    "source_rows <- rep(seq_len(nrow(records)), lengths(matched))\n",
    "link_index <- unlist(matched, use.names = FALSE)\n",
    "joined <- records[source_rows, , drop = FALSE]\n",
    "rownames(joined) <- NULL\n",
    "opcc_code_col <- \"opcc_postal_code\"\n",
    "if (opcc_code_col %in% names(joined)) {\n",
    "  opcc_code_col <- \".opcc_join_postal_code\"\n",
    "  while (opcc_code_col %in% names(joined)) {\n",
    "    opcc_code_col <- paste0(opcc_code_col, \"_\")\n",
    "  }\n",
    "}\n",
    "joined[[opcc_code_col]] <- keys[source_rows]\n",
    "link_values <- links[link_index, setdiff(names(links), \"postal_code\"), drop = FALSE]\n",
    "link_source_names <- names(link_values)\n",
    "link_names <- link_source_names\n",
    "for (i in seq_along(link_names)) {\n",
    "  while (link_names[[i]] %in% c(names(joined), link_names[seq_len(i - 1L)])) {\n",
    "    link_names[[i]] <- paste0(\"opcc_\", link_names[[i]])\n",
    "  }\n",
    "}\n",
    "names(link_values) <- link_names\n",
    "rownames(link_values) <- NULL\n",
    "joined <- cbind(joined, link_values)\n",
    "da_col <- link_names[match(\"DAUID\", link_source_names)]\n",
    "\n",
    "matched_rows <- !is.na(joined[[da_col]])\n",
    "codes_by_da <- split(joined[[opcc_code_col]][matched_rows], ",
    "joined[[da_col]][matched_rows])\n",
    "\n",
    "dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)\n",
    "utils::write.csv(joined, file.path(output_dir, \"opcc_postal_da.csv\"), ",
    "row.names = FALSE)\n",
    "\n",
    "# Map of the matched dissemination areas (StatCan 2021, OGL-Canada).\n",
    "da_boundaries <- download_da_boundaries()\n",
    "da_sf <- sf::st_read(da_boundaries$da, quiet = TRUE)\n",
    "da_sf <- da_sf[da_sf$PRUID == \"35\", ]\n",
    "# Simplify in projected EPSG:3347 metres, then back to WGS84 for leaflet.\n",
    "da_sf <- sf::st_transform(da_sf, 3347)\n",
    "da_sf <- sf::st_simplify(da_sf, preserveTopology = FALSE, dTolerance = 50)\n",
    "da_sf <- sf::st_transform(da_sf, 4326)\n",
    "da_matched <- da_sf[da_sf$DAUID %in% unique(joined[[da_col]][matched_rows]), ]\n",
    "\n",
    "html_escape <- function(x) {\n",
    "  x <- gsub(\"&\", \"&amp;\", x, fixed = TRUE)\n",
    "  x <- gsub(\"<\", \"&lt;\", x, fixed = TRUE)\n",
    "  x <- gsub(\">\", \"&gt;\", x, fixed = TRUE)\n",
    "  gsub(\"\\\"\", \"&quot;\", x, fixed = TRUE)\n",
    "}\n",
    "\n",
    "if (nrow(da_matched) == 0L) {\n",
    "  message(\"No matched dissemination areas; skipping opcc_map.html.\")\n",
    "} else {\n",
    "  popup <- vapply(seq_len(nrow(da_matched)), function(i) {\n",
    "    id <- as.character(da_matched$DAUID[[i]])\n",
    "    codes_here <- sort(unique(codes_by_da[[id]]))\n",
    "    sprintf(\"<b>%s</b><br>%d postal code(s): %s\", html_escape(id),\n",
    "            length(codes_here),\n",
    "            paste(html_escape(codes_here), collapse = \", \"))\n",
    "  }, character(1))\n",
    "  bounds <- sf::st_bbox(da_matched)\n",
    "  map <- leaflet::leaflet() |>\n",
    "    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) |>\n",
    "    leaflet::addPolygons(\n",
    "      data = da_matched,\n",
    "      fillColor = \"#2a78d6\", fillOpacity = 0.4,\n",
    "      color = \"#1b4f8f\", weight = 1,\n",
    "      popup = popup, group = \"Matched dissemination areas\"\n",
    "    ) |>\n",
    "    leaflet::fitBounds(bounds[[\"xmin\"]], bounds[[\"ymin\"]],\n",
    "                       bounds[[\"xmax\"]], bounds[[\"ymax\"]])\n",
    "  htmlwidgets::saveWidget(map, file.path(output_dir, \"opcc_map.html\"), ",
    "selfcontained = TRUE)\n",
    "  unlink(file.path(output_dir, \"opcc_map_files\"), recursive = TRUE)\n",
    "}\n"
  )
}

.postal_points_sf <- function(points, joined) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("The 'sf' package is required to build a postal-code point shapefile.",
         call. = FALSE)
  }
  postal_code_col <- attr(joined, "opcc_postal_code_col")
  if (is.null(postal_code_col)) postal_code_col <- "opcc_postal_code"
  dauid_col <- attr(joined, "opcc_dauid_col")
  if (is.null(dauid_col)) dauid_col <- "DAUID"
  if (!postal_code_col %in% names(joined)) {
    postal_code_col <- "opcc_postal_code"
  }
  if (!dauid_col %in% names(joined)) {
    dauid_col <- "DAUID"
  }

  da_col <- joined[[dauid_col]]
  code_col <- joined[[postal_code_col]]
  matched_rows <- !is.na(da_col)
  codes_matched <- code_col[matched_rows]
  da_matched <- da_col[matched_rows]

  all_codes <- unique(points$postal_code)
  da_lookup <- split(da_matched, codes_matched)

  n_da <- integer(length(all_codes))
  dauid <- character(length(all_codes))
  matched <- character(length(all_codes))
  for (i in seq_along(all_codes)) {
    code <- all_codes[[i]]
    values <- if (code %in% names(da_lookup)) {
      unique(da_lookup[[code]][!is.na(da_lookup[[code]])])
    } else {
      character(0)
    }
    if (length(values) > 0L) {
      matched[[i]] <- "Y"
      n_da[[i]] <- as.integer(length(values))
      dauid[[i]] <- paste(sort(values), collapse = ",")
    } else {
      matched[[i]] <- "N"
      n_da[[i]] <- 0L
      dauid[[i]] <- ""
    }
  }

  first_idx <- match(all_codes, points$postal_code)
  df <- data.frame(
    pcode = all_codes,
    src = points$point_source[first_idx],
    method = points$point_method[first_idx],
    matched = matched,
    n_da = n_da,
    dauid = dauid,
    latitude = points$latitude[first_idx],
    longitude = points$longitude[first_idx],
    stringsAsFactors = FALSE
  )

  df$dauid <- vapply(df$dauid, function(x) {
    if (nchar(x) > 254L) {
      paste0(substr(x, 1L, 251L), "...")
    } else {
      x
    }
  }, character(1), USE.NAMES = FALSE)

  sf::st_as_sf(df, coords = c("longitude", "latitude"), crs = 4326)
}

.write_postal_points_shapefile <- function(x, zipfile) {
  tmpdir <- tempfile("opcc_postal_points_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  dir.create(tmpdir, recursive = TRUE, showWarnings = FALSE)
  shp_path <- file.path(tmpdir, "opcc_postal_points.shp")
  sf::st_write(x, shp_path, quiet = TRUE)
  sidecars <- list.files(tmpdir, pattern = "^opcc_postal_points\\.", full.names = TRUE)
  status <- utils::zip(zipfile, files = sidecars, flags = "-j9Xq")
  if (!identical(as.integer(status), 0L) || !file.exists(zipfile)) {
    stop("Could not write the postal point shapefile archive.", call. = FALSE)
  }
  invisible(zipfile)
}
