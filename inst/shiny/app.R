library(shiny)
library(bslib)
library(DT)
library(leaflet)

if (utils::packageVersion("bslib") < "0.6.0") {
  stop(
    "The OPCC Shiny app requires bslib >= 0.6.0; ",
    "installed: ", utils::packageVersion("bslib")
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Read from the installed package so the badge cannot drift from DESCRIPTION.
# Sourced from a namespace child during a build or check, the package may not
# be installed yet, so fall back rather than failing to start.
opcc_app_version <- tryCatch(
  as.character(utils::packageVersion("OPCC")),
  error = function(e) "development"
)

# The dissemination area boundaries are loaded synchronously, inside the same
# withProgress() as the rest of the join. An earlier version ran this in a
# future/multisession worker; under load the session deadlocked writing the
# task payload to the worker socket, which froze Shiny's single event loop and
# left the UI completely unresponsive - no progress, no popup, no redraw.
da_artifact_cache_dir <- function() {
  configured <- getOption("OPCC.shiny_da_cache_dir", NULL)
  if (is.null(configured)) {
    configured <- Sys.getenv("OPCC_SHINY_DA_CACHE_DIR", unset = "")
  }
  if (identical(configured, "")) return(NULL)
  if (!is.character(configured) || length(configured) != 1L ||
      is.na(configured) || !nzchar(configured)) {
    stop("OPCC Shiny DA cache must be a single non-empty path", call. = FALSE)
  }
  dir.create(configured, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(configured)) {
    stop("Could not create OPCC Shiny DA cache: ", configured, call. = FALSE)
  }
  normalizePath(configured, mustWork = TRUE)
}

read_da_artifact <- function(path) {
  if (!file.exists(path) || isTRUE(file.info(path)$size == 0)) return(NULL)
  value <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!inherits(value, "sf") ||
      !all(c("DAUID", "PRUID") %in% names(value))) NULL else value
}

save_da_artifact <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(paste0(basename(path), "."), tmpdir = dirname(path))
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  saveRDS(value, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish simplified DA cache", call. = FALSE)
  }
  invisible(path)
}

da_lock_owner_path <- function(lock) file.path(lock, "owner.rds")

write_da_lock_owner <- function(lock, owner) {
  path <- da_lock_owner_path(lock)
  temporary <- tempfile("owner.", tmpdir = lock)
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  saveRDS(owner, temporary)
  if (!file.rename(temporary, path)) return(FALSE)
  TRUE
}

da_process_alive <- function(pid) {
  if (.Platform$OS.type == "windows") {
    output <- tryCatch(
      system2(
        "tasklist",
        c("/FI", shQuote(sprintf("PID eq %d", as.integer(pid))),
          "/FO", "CSV", "/NH"),
        stdout = TRUE, stderr = FALSE
      ),
      error = function(e) NULL
    )
    if (is.null(output) || !is.null(attr(output, "status"))) return(NA)
    listed_pids <- sub('^"[^"]+","([0-9]+)".*$', "\\1", output)
    return(any(listed_pids == as.character(as.integer(pid))))
  }
  tryCatch(tools::pskill(pid, 0L), error = function(e) NA)
}

da_lock_is_stale <- function(lock, stale_after = 7200,
                             now = Sys.time(),
                             process_alive = da_process_alive) {
  owner <- tryCatch(readRDS(da_lock_owner_path(lock)), error = function(e) NULL)
  if (!is.list(owner) || is.null(owner$host) || is.null(owner$pid) ||
      is.null(owner$heartbeat)) {
    age <- as.numeric(difftime(now, file.info(lock)$mtime, units = "secs"))
    return(is.finite(age) && age > stale_after)
  }
  if (identical(owner$host, unname(Sys.info()[["nodename"]]))) {
    alive <- process_alive(owner$pid)
    if (isTRUE(alive)) return(FALSE)
    if (identical(alive, FALSE)) return(TRUE)
  }
  age <- as.numeric(difftime(
    now, file.info(da_lock_owner_path(lock))$mtime, units = "secs"
  ))
  is.finite(age) && age > stale_after
}

refresh_da_lock <- function(lock, owner) {
  owner$heartbeat <- Sys.time()
  current <- tryCatch(readRDS(da_lock_owner_path(lock)),
                      error = function(e) NULL)
  if (!is.list(current) || !identical(current$host, owner$host) ||
      !identical(current$pid, owner$pid) ||
      !isTRUE(Sys.setFileTime(da_lock_owner_path(lock), owner$heartbeat))) {
    stop("Lost ownership of simplified DA cache lock", call. = FALSE)
  }
  owner
}

build_da_simplified <- function(tolerance, raw_cache_dir,
                                heartbeat = function() NULL) {
  heartbeat()
  old_timeout <- options(timeout = max(900, getOption("timeout", 60)))
  on.exit(options(old_timeout), add = TRUE)
  paths <- OPCC::download_da_boundaries(cache_dir = raw_cache_dir)
  heartbeat()
  da_sf <- sf::st_read(paths$da, quiet = TRUE)
  heartbeat()
  da_sf <- da_sf[da_sf$PRUID == "35", ]
  da_sf <- sf::st_transform(da_sf, 3347)
  da_sf <- sf::st_simplify(da_sf, preserveTopology = FALSE,
                           dTolerance = tolerance)
  da_sf <- sf::st_transform(da_sf, 4326)
  heartbeat()
  da_sf
}

load_da_simplified <- function(tolerance, raw_cache_dir,
                               artifact_cache_dir = NULL,
                               lock_timeout = 600,
                               stale_after = 7200) {
  artifact_dir <- artifact_cache_dir %||% raw_cache_dir
  rds <- file.path(
    artifact_dir,
    sprintf("opcc-da-on-2021-simplified-%sm.rds", tolerance)
  )
  cached <- read_da_artifact(rds)
  if (!is.null(cached)) return(cached)

  lock <- NULL
  owner <- NULL
  if (!is.null(artifact_cache_dir)) {
    lock <- paste0(rds, ".lock")
    deadline <- Sys.time() + lock_timeout
    while (!dir.create(lock, showWarnings = FALSE)) {
      cached <- read_da_artifact(rds)
      if (!is.null(cached)) return(cached)
      if (da_lock_is_stale(lock, stale_after = stale_after)) {
        stale_lock <- paste0(lock, ".stale-", Sys.getpid(), "-",
                             sprintf("%08x", sample.int(.Machine$integer.max, 1)))
        if (file.rename(lock, stale_lock)) {
          unlink(stale_lock, recursive = TRUE, force = TRUE)
          next
        }
      }
      if (Sys.time() >= deadline) {
        # Another process may still be building. Build safely in this
        # session, but do not contend for or overwrite its shared artifact.
        artifact_dir <- raw_cache_dir
        rds <- file.path(artifact_dir, basename(rds))
        lock <- NULL
        break
      }
      Sys.sleep(0.25)
    }
    if (!is.null(lock)) {
      on.exit(unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
      owner <- list(
        host = unname(Sys.info()[["nodename"]]), pid = Sys.getpid(),
        heartbeat = Sys.time()
      )
      if (!write_da_lock_owner(lock, owner)) {
        stop("Could not record simplified DA cache lock ownership",
             call. = FALSE)
      }
      cached <- read_da_artifact(rds)
      if (!is.null(cached)) return(cached)
    }
  }
  # A truncated or wrong-type RDS must not block atomic publication on
  # platforms where file.rename() cannot replace an existing destination.
  if (file.exists(rds)) unlink(rds, force = TRUE)
  heartbeat <- if (is.null(owner)) function() NULL else function() {
    owner <<- refresh_da_lock(lock, owner)
  }
  da_sf <- build_da_simplified(tolerance, raw_cache_dir, heartbeat)
  save_da_artifact(da_sf, rds)
  da_sf
}

da_simplify_tolerance <- 50
da_fill_color <- "#2a78d6"
da_border_color <- "#1b4f8f"
point_color <- "#e4572e"
phu_color <- "#5f6b7a"

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

codes_per_da <- function(joined) {
  da_col <- attr(joined, "opcc_dauid_col") %||% "DAUID"
  rows <- !is.na(joined[[da_col]])
  if (!any(rows)) {
    return(list())
  }
  code_col <- attr(joined, "opcc_postal_code_col") %||% "opcc_postal_code"
  split(joined[[code_col]][rows], joined[[da_col]][rows])
}

das_per_code <- function(joined) {
  da_col <- attr(joined, "opcc_dauid_col") %||% "DAUID"
  rows <- !is.na(joined[[da_col]])
  if (!any(rows)) return(list())
  code_col <- attr(joined, "opcc_postal_code_col") %||% "opcc_postal_code"
  lapply(split(joined[[da_col]][rows], joined[[code_col]][rows]),
         function(x) sort(unique(x)))
}

codes_by_da_label <- function(codes_list, dauid) {
  codes <- sort(unique(codes_list[[dauid]] %||% character()))
  label <- paste(html_escape(head(codes, 12L)), collapse = ", ")
  if (length(codes) > 12L) {
    label <- paste0(label, sprintf(", ... (%d total)", length(codes)))
  }
  list(n = length(codes), label = label)
}

da_popup <- function(da_matched, codes_list) {
  vapply(seq_len(nrow(da_matched)), function(i) {
    id <- as.character(da_matched$DAUID[[i]])
    codes <- codes_by_da_label(codes_list, id)
    sprintf("<b>%s</b><br>%d postal code(s): %s", html_escape(id),
            codes$n, codes$label)
  }, character(1))
}

point_popup <- function(points, da_lookup) {
  vapply(seq_len(nrow(points)), function(i) {
    code <- points$postal_code[[i]]
    das <- da_lookup[[code]] %||% character()
    da_note <- if (length(das) == 0L) {
      "No matched dissemination area"
    } else {
      sprintf("Matched DA: %s", paste(head(das, 6L), collapse = ", "))
    }
    sprintf("<b>%s</b><br>%s (%s)<br>%s",
            html_escape(code),
            html_escape(points$point_source[[i]]),
            html_escape(points$point_method[[i]]),
            html_escape(da_note))
  }, character(1))
}

# Optional public health unit overlay. OPCC does not ship or fetch the
# boundaries: the overlay draws only if the user has placed phu_simple.rds in
# the app cache themselves. Nothing here depends on a package outside
# DESCRIPTION, and the map degrades to no overlay when the file is absent.
load_local_phu <- function() {
  rds <- file.path(tools::R_user_dir("OPCC", "cache"), "shiny-app",
                   "phu_simple.rds")
  if (!file.exists(rds)) {
    return(NULL)
  }
  tryCatch(readRDS(rds), error = function(e) NULL)
}

base_map_groups <- c(
  "Light (CartoDB Positron)" = "CartoDB.Positron",
  "Streets (CartoDB Voyager)" = "CartoDB.Voyager",
  "Dark (CartoDB Dark Matter)" = "CartoDB.DarkMatter",
  "OpenStreetMap" = "OpenStreetMap",
  "Satellite (Esri World Imagery)" = "Esri.WorldImagery"
)

build_da_map <- function(da_matched, joined, points = NULL, phu = NULL) {
  codes_list <- codes_per_da(joined)
  da_lookup <- das_per_code(joined)
  bounds <- sf::st_bbox(da_matched)
  map <- leaflet::leaflet()
  for (i in seq_along(base_map_groups)) {
    map <- leaflet::addProviderTiles(
      map,
      leaflet::providers[[base_map_groups[[i]]]],
      group = names(base_map_groups)[[i]]
    )
  }
  overlay_groups <- c("Matched dissemination areas", "Postal code points")
  if (!is.null(phu) && nrow(phu) > 0L) {
    map <- leaflet::addPolygons(
      map,
      data = phu,
      fill = FALSE, color = phu_color, weight = 1.3, opacity = 0.85,
      popup = ~paste0("<b>", html_escape(PHU_NAME_ENG), "</b>"),
      group = "Public Health Unit boundaries"
    )
    overlay_groups <- c(overlay_groups, "Public Health Unit boundaries")
  }
  map <- leaflet::addPolygons(
    map,
    data = da_matched,
    fillColor = da_fill_color, fillOpacity = 0.4,
    color = da_border_color, weight = 1,
    popup = da_popup(da_matched, codes_list),
    group = "Matched dissemination areas"
  ) |>
    leaflet::fitBounds(bounds[["xmin"]], bounds[["ymin"]],
                       bounds[["xmax"]], bounds[["ymax"]])
  legend_colors <- da_fill_color
  legend_labels <- "Matched dissemination area"
  if (!is.null(points) && nrow(points) > 0L) {
    map <- leaflet::addCircleMarkers(
      map,
      data = points,
      lng = ~longitude, lat = ~latitude,
      radius = 4, color = point_color, fillOpacity = 0.9, weight = 1,
      popup = point_popup(points, da_lookup),
      group = "Postal code points"
    )
    legend_colors <- c(legend_colors, point_color)
    legend_labels <- c(legend_labels, "Postal code point")
  }
  if (!is.null(phu) && nrow(phu) > 0L) {
    legend_colors <- c(legend_colors, phu_color)
    legend_labels <- c(legend_labels, "Public Health Unit boundary")
  }
  map <- leaflet::addLegend(
    map, position = "bottomleft",
    colors = legend_colors, labels = legend_labels, title = NULL
  )
  map <- leaflet::addLayersControl(
    map,
    baseGroups = names(base_map_groups),
    overlayGroups = overlay_groups,
    options = leaflet::layersControlOptions(collapsed = FALSE)
  )
  map
}

download_or_disabled <- function(items) {
  tagList(lapply(items, function(item) {
    if (isTRUE(item$ready)) {
      downloadButton(item$id, item$label,
                     class = "btn-opcc-download w-100 mb-1")
    } else {
      tags$button(
        item$label, type = "button",
        class = "btn btn-outline-secondary w-100 mb-1",
        disabled = "disabled"
      )
    }
  }))
}

da_vintages <- rev(OPCC::list_vintages("DA"))
latest_da_vintage <- da_vintages[[1]]

status_colors <- c(success = "#198754", error = "#dc3545", warning = "#e8590c")

show_status_popup <- function(kind, title_text, ...) {
  showModal(modalDialog(
    title = NULL,
    tags$div(
      class = "opcc-modal-band",
      style = sprintf("background: %s;", status_colors[[kind]]),
      title_text),
    tagList(list(...)),
    easyClose = TRUE,
    footer = modalButton("OK")
  ))
}

join_status_text <- function(meta, n_out) {
  status <- sprintf(
    "%s input row(s) in, %s row(s) out, %s postal code(s) unmatched, %s invalid value(s).",
    format(meta$n_input, big.mark = ","),
    format(n_out, big.mark = ","),
    format(length(meta$unmatched), big.mark = ","),
    format(meta$invalid_count, big.mark = ","))
  if (length(meta$unmatched) > 0L) {
    status <- paste(status, sprintf("Unmatched: %s",
      paste(head(meta$unmatched, 8L), collapse = ", ")))
  }
  status
}

app_css <- "
body {
  letter-spacing: 0.005em;
}
.opcc-shell {
  min-height: 100vh;
  background:
    radial-gradient(circle at 88% 8%, rgba(22, 138, 173, 0.12), transparent 28rem),
    #eef4f8;
}
.opcc-brand {
  display: flex;
  align-items: center;
  gap: 0.9rem;
  color: #ffffff;
  padding: 0.25rem 0;
}
.opcc-brand-mark {
  display: grid;
  place-items: center;
  width: 3.1rem;
  height: 3.1rem;
  flex: 0 0 auto;
  border: 1px solid rgba(255, 255, 255, 0.45);
  border-radius: 0.9rem;
  background: linear-gradient(145deg, #16a6a1, #08778c);
  box-shadow: 0 0.45rem 1.2rem rgba(3, 38, 54, 0.24);
  font-size: 0.72rem;
  font-weight: 800;
  letter-spacing: 0.08em;
}
.opcc-brand h1 {
  margin: 0;
  color: #ffffff;
  font-size: clamp(1rem, 1.5vw, 1.35rem);
  font-weight: 750;
  line-height: 1.18;
}
.opcc-brand-title {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 0.5rem;
}
.opcc-version {
  flex: 0 0 auto;
  padding: 0.1rem 0.5rem;
  border: 1px solid rgba(255, 255, 255, 0.35);
  border-radius: 0.6rem;
  background: rgba(255, 255, 255, 0.12);
  color: #d9eef2;
  font-size: 0.72rem;
  font-weight: 650;
  letter-spacing: 0.02em;
  white-space: nowrap;
}
.opcc-brand p {
  margin: 0.18rem 0 0;
  color: #badde4;
  font-size: 0.78rem;
  font-weight: 500;
}
body.bslib-page-sidebar > .navbar {
  min-height: 5rem;
  border: 0;
  background: linear-gradient(105deg, #102f46 0%, #0a5368 60%, #08778c 100%);
  box-shadow: 0 0.35rem 1.4rem rgba(16, 47, 70, 0.2);
}
.opcc-control-panel {
  border: 0 !important;
  border-right: 1px solid #dbe7ed !important;
  box-shadow: 0.45rem 0 1.5rem rgba(23, 55, 73, 0.06);
}
.opcc-sidebar-intro {
  padding: 0.2rem 0 0.75rem;
}
.opcc-sidebar-intro h2 {
  margin: 0;
  color: #173749;
  font-size: 1.15rem;
  font-weight: 750;
}
.opcc-sidebar-intro p {
  margin: 0.35rem 0 0;
  color: #607987;
  font-size: 0.84rem;
  line-height: 1.45;
}
.opcc-section-title {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 1.15rem 0 0.55rem;
  color: #08778c;
  font-size: 0.73rem;
  font-weight: 800;
  letter-spacing: 0.09em;
  text-transform: uppercase;
}
.opcc-step {
  display: inline-grid;
  place-items: center;
  width: 1.45rem;
  height: 1.45rem;
  border-radius: 50%;
  background: #dff3f4;
  color: #076775;
  font-size: 0.68rem;
}
.opcc-control-panel .form-control,
.opcc-control-panel .selectize-input {
  border-color: #c7d9e1;
  border-radius: 0.65rem;
  background: #fbfdfe;
}
.opcc-control-panel .form-control:focus,
.opcc-control-panel .selectize-input.focus {
  border-color: #1598a2;
  box-shadow: 0 0 0 0.22rem rgba(21, 152, 162, 0.14);
}
.opcc-control-panel .shiny-options-group {
  line-height: 1.35;
}
.opcc-vintage {
  padding: 0.65rem 0.75rem;
  border: 1px solid #d7e8ed;
  border-radius: 0.65rem;
  background: #eff8fa;
  color: #315b68;
  font-size: 0.78rem;
}
.opcc-join-button {
  min-height: 2.85rem;
  margin-top: 0.8rem;
  border: 0;
  border-radius: 0.7rem;
  background: linear-gradient(100deg, #08778c, #0b8e8a);
  box-shadow: 0 0.5rem 1rem rgba(8, 119, 140, 0.2);
  font-weight: 750;
}
.opcc-join-button:hover,
.opcc-join-button:focus {
  background: linear-gradient(100deg, #08687a, #087b78);
  transform: translateY(-1px);
}
.opcc-downloads {
  padding: 0.75rem;
  border: 1px solid #e2e9ed;
  border-radius: 0.75rem;
  background: #f7fafb;
}
.opcc-downloads .btn {
  border-radius: 0.55rem;
  font-size: 0.78rem;
  text-align: left;
}
.opcc-downloads .btn-opcc-download {
  border: 0;
  background: #0b8e8a;
  color: #ffffff;
  font-weight: 600;
}
.opcc-downloads .btn-opcc-download:hover,
.opcc-downloads .btn-opcc-download:focus {
  background: #087b78;
  color: #ffffff;
  box-shadow: 0 0.25rem 0.6rem rgba(8, 119, 140, 0.25);
}
.opcc-results-workspace {
  display: flex;
  min-width: 0;
  height: 100%;
  flex-direction: column;
  gap: 0.9rem;
}
.opcc-workspace-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  flex-wrap: wrap;
  padding: 0.15rem 0.2rem;
}
.opcc-workspace-heading h2 {
  margin: 0;
  color: #173749;
  font-size: 1.35rem;
  font-weight: 750;
}
.opcc-workspace-heading p {
  margin: 0.18rem 0 0;
  color: #627b89;
  font-size: 0.86rem;
}
.opcc-result-summary {
  display: flex;
  gap: 0.45rem;
  flex-wrap: wrap;
}
.opcc-stat {
  padding: 0.45rem 0.7rem;
  border: 1px solid #d8e7ec;
  border-radius: 999px;
  background: #ffffff;
  color: #355766;
  font-size: 0.75rem;
  font-weight: 650;
  box-shadow: 0 0.2rem 0.7rem rgba(35, 71, 88, 0.05);
}
.opcc-stat-ready {
  border-color: #a7ddd3;
  background: #e9f8f4;
  color: #166b59;
}
.opcc-results-card {
  flex: 1 1 auto;
  min-height: 32rem;
}
.opcc-results-card > .card {
  height: 100%;
  border: 1px solid rgba(194, 214, 223, 0.75) !important;
  border-radius: 1rem !important;
  box-shadow: 0 0.8rem 2.25rem rgba(31, 68, 86, 0.1) !important;
  overflow: hidden;
}
.opcc-results-card > .card .nav-underline {
  gap: 1.25rem;
}
.opcc-results-card .nav-link {
  color: #617985;
  font-weight: 700;
}
.opcc-results-card .nav-link.active {
  color: #08778c;
}
.opcc-data-wrap,
.opcc-map-wrap {
  position: relative;
  width: 100%;
  height: 100%;
  min-height: 28rem;
}
.opcc-empty-state {
  position: absolute;
  inset: 0;
  z-index: 500;
  display: flex;
  align-items: center;
  justify-content: center;
  background:
    radial-gradient(circle at 50% 42%, rgba(24, 166, 161, 0.09), transparent 15rem),
    rgba(248, 251, 252, 0.96);
  text-align: center;
  padding: 2rem;
}
.opcc-empty-state-inner {
  max-width: 26rem;
}
.opcc-empty-symbol {
  display: grid;
  place-items: center;
  width: 4.2rem;
  height: 4.2rem;
  margin: 0 auto 1rem;
  border-radius: 1.25rem;
  background: linear-gradient(145deg, #d8f1f1, #e8f0fa);
  color: #08778c;
  font-size: 1.5rem;
  font-weight: 800;
  box-shadow: inset 0 0 0 1px rgba(8, 119, 140, 0.12);
}
.opcc-overlay-title {
  color: #173749;
  font-size: 1.05rem;
  font-weight: 750;
}
.opcc-overlay-note {
  margin-top: 0.35rem;
  color: #637c89;
  font-size: 0.86rem;
  line-height: 1.5;
}
.opcc-modal-band {
  color: #ffffff;
  font-size: 1.02rem;
  font-weight: 650;
  padding: 0.65rem 0.95rem;
  border-radius: 0.65rem;
  margin-bottom: 0.85rem;
}
@media (max-width: 767.98px) {
  .opcc-brand-mark {
    width: 2.5rem;
    height: 2.5rem;
  }
  .opcc-brand p {
    display: none;
  }
  .opcc-results-workspace {
    min-height: 38rem;
  }
}
"

app_theme <- bslib::bs_theme(
  version = 5,
  preset = "shiny",
  primary = "#08778c",
  secondary = "#e2783f",
  success = "#23866b",
  info = "#247ba0",
  warning = "#d88724",
  danger = "#c94c56",
  bg = "#eef4f8",
  fg = "#173749",
  "border-radius" = "0.7rem",
  "font-family-sans-serif" = paste(
    "Inter, Aptos, Segoe UI, Roboto, Helvetica Neue, Arial, sans-serif"
  )
) |>
  bslib::bs_add_rules(app_css)

ui <- bslib::page_sidebar(
  window_title = paste0(
    "Open Postal Code Correspondence to Dissemination Areas (v",
    opcc_app_version, ")"
  ),
  theme = app_theme,
  class = "bslib-page-dashboard opcc-shell",
  title = tags$div(
    class = "opcc-brand",
    tags$div(class = "opcc-brand-mark", "OPCC"),
    tags$div(
      tags$div(
        class = "opcc-brand-title",
        tags$h1("Open Postal Code Correspondence to Dissemination Areas"),
        tags$span(class = "opcc-version",
                  title = "Installed OPCC package version",
                  paste0("v", opcc_app_version))
      ),
      tags$p("Ontario postal codes to census geography, openly and reproducibly")
    )
  ),
  sidebar = bslib::sidebar(
    width = 360,
    class = "opcc-control-panel",
    bg = "#ffffff",
    tags$div(
      class = "opcc-sidebar-intro",
      tags$h2("Build a correspondence"),
      tags$p(
        "Enter postal codes or upload a table, then join them to the latest ",
        "available dissemination-area correspondence."
      )
    ),
    tags$div(
      class = "opcc-section-title",
      tags$span(class = "opcc-step", "1"),
      "Choose your input"
    ),
    radioButtons(
      "input_mode",
      NULL,
      choices = c(
        "Enter postal codes" = "text",
        "Upload a CSV" = "file"
      ),
      selected = "text"
    ),
    conditionalPanel(
      condition = "input.input_mode == 'text'",
      textAreaInput(
        "postcode_text",
        "Postal codes",
        height = "110px",
        placeholder = "M5V 3A8\nK1A 0B1\nN6A 3K7"
      ),
      tags$p(class = "text-muted small", "One postal code per line.")
    ),
    conditionalPanel(
      condition = "input.input_mode == 'file'",
      fileInput(
        "input_file",
        "Upload a CSV",
        accept = c(".csv", "text/csv"),
        buttonLabel = "Browse...",
        placeholder = "CSV with a postal-code column"
      )
    ),
    uiOutput("postal_col_ui"),
    tags$div(
      class = "opcc-section-title",
      tags$span(class = "opcc-step", "2"),
      "Set the join rule"
    ),
    radioButtons(
      "all_links",
      "Multiple dissemination areas",
      choices = c(
        "Keep one best link per postal code" = "best",
        "Return every link" = "all"
      ),
      selected = "best"
    ),
    tags$p(
      class = "text-muted small",
      paste(
        "About 7.8% of Ontario postal codes span more than one",
        "dissemination area. Returning every link can create multiple",
        "output rows for one input record."
      )
    ),
    tags$div(
      class = "opcc-vintage",
      sprintf("Correspondence vintage: %s (latest)", latest_da_vintage)
    ),
    actionButton(
      "run_join",
      "Join postal codes to areas",
      class = "btn-primary opcc-join-button w-100"
    ),
    tags$div(
      class = "opcc-section-title",
      tags$span(class = "opcc-step", "3"),
      "Download results"
    ),
    tags$div(class = "opcc-downloads", uiOutput("downloads_ui"))
  ),
  tags$main(
    class = "opcc-results-workspace",
    tags$div(
      class = "opcc-workspace-heading",
      tags$div(
        tags$h2("Results workspace"),
        tags$p("Join once, then inspect the correspondence as data or a map.")
      ),
      uiOutput("result_summary")
    ),
    tags$div(
      class = "opcc-results-card",
      bslib::navset_card_underline(
        id = "output_tab",
        height = "100%",
        full_screen = TRUE,
        bslib::nav_panel(
          "Data",
          tags$div(
            class = "opcc-data-wrap",
            DT::dataTableOutput("joined_table"),
            uiOutput("data_status")
          )
        ),
        bslib::nav_panel(
          "Map",
          tags$div(
            class = "opcc-map-wrap",
            leaflet::leafletOutput("da_map", height = "100%"),
            uiOutput("map_status")
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # Boundary source files are large rebuild inputs, so they must not enter
  # OPCC's persistent runtime cache. Keep raw downloads/extracts in a directory
  # owned by this Shiny session and remove it when the session ends. Only the
  # derived RDS may use an explicitly configured operator directory.
  raw_cache_dir <- tempfile("opcc-shiny-session-", tmpdir = tempdir())
  dir.create(raw_cache_dir, recursive = TRUE, showWarnings = FALSE)
  artifact_cache_dir <- da_artifact_cache_dir()
  session$onSessionEnded(function() {
    unlink(raw_cache_dir, recursive = TRUE, force = TRUE)
  })


  records_rv <- reactiveVal(NULL)
  joined_rv <- reactiveVal(NULL)
  join_meta_rv <- reactiveVal(NULL)
  postal_points_rv <- reactiveVal(NULL)
  da_matched_rv <- reactiveVal(NULL)
  phu_rv <- reactiveVal(load_local_phu())
  correspondence_rv <- reactiveVal(NULL)
  centroids_rv <- reactiveVal(NULL)

  observeEvent(input$input_file, {
    req(input$input_file)
    records <- tryCatch(
      suppressWarnings(utils::read.csv(input$input_file$datapath,
        stringsAsFactors = FALSE, check.names = FALSE)),
      error = function(e) e
    )
    if (inherits(records, "error")) {
      records_rv(NULL)
      joined_rv(NULL)
      join_meta_rv(NULL)
      da_matched_rv(NULL)
      show_status_popup("error", "File error",
        tags$p(sprintf("Could not read the file: %s",
                       conditionMessage(records))))
      return()
    }
    records_rv(records)
    joined_rv(NULL)
    join_meta_rv(NULL)
    postal_points_rv(NULL)
    da_matched_rv(NULL)
  })

  output$postal_col_ui <- renderUI({
    if (identical(input$input_mode, "file")) {
      records <- records_rv()
      if (is.null(records)) {
        return(tags$p(class = "text-muted small",
                      "Upload a CSV to choose its postal code column."))
      }
      guess <- .detect_postal_column(records)
      return(selectInput("postal_col", "Postal code column",
        choices = colnames(records),
        selected = if (!is.na(guess)) guess))
    }
    tags$p(class = "text-muted small",
      paste("Typed codes are joined as a single postal_code column;",
            "letter case and extra spacing do not matter."))
  })

  observeEvent(input$run_join, {
    req(latest_da_vintage)
    if (identical(input$input_mode, "file")) {
      records <- records_rv()
      if (is.null(records) || is.null(input$postal_col)) {
        show_status_popup("warning", "Missing input",
          tags$p("Upload a CSV and choose its postal code column first."))
        return()
      }
      postal_col <- input$postal_col
      typed_codes <- NULL
    } else {
      typed_codes <- .parse_postal_text(input$postcode_text)
      if (length(typed_codes) == 0L) {
        show_status_popup("warning", "Missing input",
          tags$p("Enter at least one postal code, one per line."))
        return()
      }
      malformed <- typed_codes[is.na(OPCC::normalize_postal_code(typed_codes))]
      if (length(malformed) > 0L) {
        show_status_popup(
          if (length(malformed) == length(typed_codes)) "error" else "warning",
          "Check the postal code format",
          tags$p(sprintf(
            "%s of %s entered value(s) are not valid Canadian postal codes:",
            format(length(malformed), big.mark = ","),
            format(length(typed_codes), big.mark = ","))),
          tags$ul(lapply(utils::head(malformed, 10L), tags$li)),
          if (length(malformed) > 10L) {
            tags$p(sprintf("...and %s more.",
                           format(length(malformed) - 10L, big.mark = ",")))
          },
          tags$p(class = "text-muted mb-0",
                 "Expected format: A1A 1A1. Correct or remove them, then join.")
        )
        if (length(malformed) == length(typed_codes)) return()
        typed_codes <- setdiff(typed_codes, malformed)
      }
      records <- data.frame(postal_code = typed_codes,
                            stringsAsFactors = FALSE)
      postal_col <- "postal_code"
    }
    all_links <- identical(input$all_links, "all")
    correspondence <- correspondence_rv()
    if (is.null(correspondence)) {
      correspondence <- tryCatch(
        shiny::withProgress(message = "Fetching DA correspondence", value = 0.3, {
          OPCC::get_da_correspondence(vintage = latest_da_vintage)
        }),
        error = function(e) e
      )
      if (!inherits(correspondence, "error")) correspondence_rv(correspondence)
    }
    if (inherits(correspondence, "error")) {
      show_status_popup("error", "Join failed",
        tags$p(conditionMessage(correspondence)))
      return()
    }
    result <- tryCatch(
      .postal_da_join(records, postal_col, correspondence,
                             all_links = all_links),
      error = function(e) e
    )
    if (inherits(result, "error")) {
      show_status_popup("error", "Join failed",
        tags$p(conditionMessage(result)))
      return()
    }
    joined_rv(result$joined)
    join_meta_rv(list(
      mode = if (is.null(typed_codes)) "file" else "text",
      typed_codes = typed_codes,
      n_input = result$n_input,
      vintage = latest_da_vintage,
      all_links = all_links,
      unmatched = result$unmatched,
      invalid_count = result$invalid_count,
      postal_code_col = result$postal_code_col,
      dauid_col = result$dauid_col
    ))
    da_matched_rv(NULL)
    input_codes <- unique(result$joined[[result$postal_code_col]])
    centroids <- centroids_rv()
    if (is.null(centroids)) {
      centroids <- tryCatch(
        shiny::withProgress(message = "Fetching postal centroids", value = 0.7, {
          .load_postal_centroids()
        }),
        error = function(e) NULL
      )
      if (!is.null(centroids)) centroids_rv(centroids)
    }
    points <- if (is.null(centroids)) NULL else
      .filter_postal_centroids(centroids, input_codes)
    if (!is.null(points) && nrow(points) > 0L) {
      postal_points_rv(points)
    } else {
      postal_points_rv(NULL)
    }
    dauid_values <- result$joined[[result$dauid_col]]
    dauids <- unique(dauid_values[!is.na(dauid_values)])
    n_points <- if (is.null(points)) 0L else nrow(points)
    if (length(dauids) > 0L) {
      # Join and map are one action. The boundary load runs here, inside the
      # same progress bar, so the user sees continuous feedback and the
      # session never hands work to a background process.
      da_sf <- tryCatch(
        shiny::withProgress(
          message = "Loading dissemination area boundaries",
          detail = if (is.null(artifact_cache_dir)) {
            "Session-only cache: each new app session rebuilds the map."
          } else {
            "Using the operator-configured reusable simplified-map cache."
          },
          value = 0.85,
          load_da_simplified(
            da_simplify_tolerance, raw_cache_dir, artifact_cache_dir
          )
        ),
        error = function(e) e
      )
      if (inherits(da_sf, "error")) {
        da_matched_rv(NULL)
        show_status_popup("error", "Boundary load failed",
          tags$p(conditionMessage(da_sf)))
        return()
      }
      da_matched <- da_sf[da_sf$DAUID %in% dauids, ]
      da_matched_rv(da_matched)
      tryCatch(
        updateTabsetPanel("output_tab", selected = "Map", session = session),
        error = function(e) invisible(NULL)
      )
      unmatched_note <- if (length(result$unmatched) > 0L) {
        sprintf(" %s postal code(s) had no DA and are not drawn as polygons.",
                length(result$unmatched))
      } else {
        ""
      }
      show_status_popup("success", "Join complete - map ready",
        tags$p(join_status_text(join_meta_rv(), nrow(result$joined))),
        tags$p(sprintf(
          "%s dissemination area(s) drawn; %s postal code point(s) on the map.%s",
          format(nrow(da_matched), big.mark = ","),
          format(n_points, big.mark = ","),
          unmatched_note)),
        tags$p(sprintf("Correspondence vintage: %s (latest).", latest_da_vintage)))
    } else {
      show_status_popup("warning", "Join complete - nothing to draw",
        tags$p(join_status_text(join_meta_rv(), nrow(result$joined))),
        tags$p(sprintf("Correspondence vintage: %s (latest)", latest_da_vintage)),
        tags$p("No matched dissemination areas to draw on the map."))
    }
  })

  output$result_summary <- renderUI({
    joined <- joined_rv()
    meta <- join_meta_rv()
    if (is.null(joined) || is.null(meta)) {
      return(tags$div(
        class = "opcc-result-summary",
        tags$span(class = "opcc-stat", "Ready for input"),
        tags$span(
          class = "opcc-stat",
          sprintf("Vintage %s", latest_da_vintage)
        )
      ))
    }
    tags$div(
      class = "opcc-result-summary",
      tags$span(
        class = "opcc-stat opcc-stat-ready",
        sprintf("%s joined rows", format(nrow(joined), big.mark = ","))
      ),
      tags$span(
        class = "opcc-stat",
        sprintf(
          "%s unmatched",
          format(length(meta$unmatched), big.mark = ",")
        )
      ),
      tags$span(
        class = "opcc-stat",
        sprintf("%s invalid", format(meta$invalid_count, big.mark = ","))
      )
    )
  })

  output$joined_table <- DT::renderDataTable({
    joined <- joined_rv()
    req(joined)
    joined
  }, rownames = FALSE, options = list(scrollX = TRUE, pageLength = 25))

  output$data_status <- renderUI({
    if (is.null(joined_rv())) {
      return(tags$div(
        class = "opcc-empty-state",
        tags$div(
          class = "opcc-empty-state-inner",
          tags$div(class = "opcc-empty-symbol", "01"),
          tags$div(class = "opcc-overlay-title", "Your joined data will appear here"),
          tags$div(
            class = "opcc-overlay-note",
            paste(
              "Use the control panel to enter postal codes or upload a CSV,",
              "then run the join."
            )
          )
        )
      ))
    }
    NULL
  })

  output$downloads_ui <- renderUI({
    joined_ready <- !is.null(joined_rv()) && nrow(joined_rv()) > 0L
    points_ready <- joined_ready && !is.null(postal_points_rv()) &&
      nrow(postal_points_rv()) > 0L
    map_ready <- joined_ready && !is.null(da_matched_rv()) &&
      nrow(da_matched_rv()) > 0L
    download_or_disabled(list(
      list(id = "dl_csv", label = "opcc_postal_da.csv", ready = joined_ready),
      list(id = "dl_points_shp", label = "opcc_postal_points.zip",
           ready = points_ready),
      list(id = "dl_map", label = "opcc_map.html", ready = map_ready),
      list(id = "dl_script", label = "reproduce.R", ready = joined_ready)
    ))
  })

  output$map_status <- renderUI({
    if (is.null(da_matched_rv())) {
      return(tags$div(
        class = "opcc-empty-state",
        tags$div(
          class = "opcc-empty-state-inner",
          tags$div(class = "opcc-empty-symbol", "DA"),
          tags$div(class = "opcc-overlay-title", "The map is created automatically"),
          tags$div(
            class = "opcc-overlay-note",
            paste(
              "After the data is joined, matched dissemination areas and",
              "postal-code points are drawn here--no extra map controls needed."
            )
          )
        )
      ))
    }
    NULL
  })

  output$dl_csv <- downloadHandler(
    filename = function() "opcc_postal_da.csv",
    content = function(file) {
      joined <- joined_rv()
      req(joined)
      utils::write.csv(joined, file, row.names = FALSE)
    }
  )

  output$dl_points_shp <- downloadHandler(
    filename = function() "opcc_postal_points.zip",
    content = function(file) {
      points <- postal_points_rv()
      joined <- joined_rv()
      req(points, joined)
      if (!requireNamespace("sf", quietly = TRUE)) {
        show_status_popup("error", "Shapefile export unavailable",
          tags$p("The sf package is required to export a shapefile."))
        return()
      }
      sf_points <- .postal_points_sf(points, joined)
      .write_postal_points_shapefile(sf_points, file)
    }
  )

  output$dl_script <- downloadHandler(
    filename = function() "reproduce.R",
    content = function(file) {
      meta <- join_meta_rv()
      req(meta)
      if (identical(meta$mode, "text")) {
        script <- .render_opcc_reproducer_script(
          input_file = NULL, postal_col = "postal_code", output_dir = ".",
          vintage = meta$vintage,
          all_links = identical(input$all_links, "all"),
          codes = unique(meta$typed_codes)
        )
      } else {
        req(input$input_file, input$postal_col)
        script <- .render_opcc_reproducer_script(
          input$input_file$name, input$postal_col, ".",
          latest_da_vintage, all_links = identical(input$all_links, "all")
        )
      }
      writeLines(script, file)
    }
  )

  output$dl_map <- downloadHandler(
    filename = function() "opcc_map.html",
    content = function(file) {
      da <- da_matched_rv()
      joined <- joined_rv()
      req(da, joined, nrow(da) > 0L)
      map <- build_da_map(da, joined, postal_points_rv(), phu_rv())
      htmlwidgets::saveWidget(map, file, selfcontained = TRUE)
    }
  )

  output$da_map <- leaflet::renderLeaflet({
    da <- da_matched_rv()
    joined <- joined_rv()
    req(da, joined, nrow(da) > 0L)
    build_da_map(da, joined, postal_points_rv(), phu_rv())
  })
}

shiny::shinyApp(ui, server)
