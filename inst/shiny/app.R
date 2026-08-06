library(shiny)
library(bslib)
library(DT)
library(leaflet)
library(promises)
library(future)

if (utils::packageVersion("shiny") < "1.8.0") {
  stop(
    "The OPCC Shiny app requires shiny >= 1.8.0 (for ExtendedTask); ",
    "installed: ", utils::packageVersion("shiny")
  )
}
if (utils::packageVersion("bslib") < "0.6.0") {
  stop(
    "The OPCC Shiny app requires bslib >= 0.6.0; ",
    "installed: ", utils::packageVersion("bslib")
  )
}

.previous_future_plan <- future::plan()
.async_plan_initialized <- FALSE
ensure_async_plan <- function() {
  if (!isTRUE(.async_plan_initialized)) {
    future::plan(future::multisession, workers = 2L)
    .async_plan_initialized <<- TRUE
  }
  invisible(NULL)
}
shiny::onStop(function() {
  if (isTRUE(.async_plan_initialized)) {
    future::plan(.previous_future_plan)
  }
})

`%||%` <- function(a, b) if (is.null(a)) b else a

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

load_local_phu <- function() {
  rds <- file.path(tools::R_user_dir("OPCC", "cache"), "shiny-app",
                   "phu_simple.rds")
  if (!file.exists(rds)) {
    src <- system.file("extdata", "phu_simple.rds", package = "ONgeoR")
    if (!nzchar(src)) {
      return(NULL)
    }
    dir.create(dirname(rds), recursive = TRUE, showWarnings = FALSE)
    file.copy(src, rds)
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
      downloadButton(item$id, item$label, class = "btn-primary w-100 mb-1")
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
    footer = NULL
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
.top-nav .nav-tabs .nav-link {
  font-weight: 600;
  letter-spacing: 0.02em;
}
.opcc-header {
  background: linear-gradient(90deg, #1b4f8f 0%, #2a78d6 100%);
  color: #ffffff;
  padding: 10px 22px;
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}
.opcc-header .opcc-title {
  font-size: 1.22rem;
  font-weight: 700;
  letter-spacing: 0.04em;
}
.opcc-header .opcc-subtitle {
  font-size: 0.9rem;
  font-weight: 400;
  opacity: 0.85;
}
.opcc-section-title {
  color: #1b4f8f;
  font-weight: 700;
  font-size: 0.78rem;
  text-transform: uppercase;
  letter-spacing: 0.09em;
  margin-top: 0.9rem;
  margin-bottom: 0.45rem;
}
.opcc-section-title:first-child {
  margin-top: 0;
}
.opcc-modal-band {
  color: #ffffff;
  font-weight: 600;
  font-size: 1.02rem;
  padding: 0.55rem 0.95rem;
  border-radius: 0.4rem;
  margin-bottom: 0.85rem;
}
"

ui <- bslib::page_fillable(
  window_title = "OPCC - Open Postal Code Correspondence",
  theme = bslib::bs_theme(
    version = 5,
    primary = da_fill_color,
    secondary = point_color,
    bg = "#f6f8fb",
    fg = "#1f2933"
  ),
  tags$style(app_css),
  tags$div(
    class = "opcc-header",
    tags$div(
      class = "opcc-title",
      "OPCC: Open Postal Code Correspondence",
      tags$div(class = "opcc-subtitle",
        "Ontario postal codes joined to census dissemination areas")
    )
  ),
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 340,
      tags$div(class = "opcc-section-title", "Postal code input"),
      radioButtons("input_mode", NULL,
        choices = c("Enter postal codes" = "text",
                    "Upload a CSV" = "file"),
        selected = "text"),
      conditionalPanel(
        condition = "input.input_mode == 'text'",
        textAreaInput("postcode_text", "Postal codes",
          height = "110px",
          placeholder = "M5V 3A8\nK1A 0B1\nN6A 3K7"),
        tags$p(class = "text-muted small",
          "One postal code per line.")
      ),
      conditionalPanel(
        condition = "input.input_mode == 'file'",
        fileInput("input_file", "Upload a CSV",
          accept = c(".csv", "text/csv"),
          buttonLabel = "Browse...",
          placeholder = "CSV with a postal-code column")
      ),
      uiOutput("postal_col_ui"),
      tags$div(class = "opcc-section-title", "Join options"),
      radioButtons("all_links", "Multiple dissemination areas",
        choices = c("Keep one best link per postal code" = "best",
                    "Return every link" = "all"),
        selected = "best"),
      tags$p(class = "text-muted small",
        paste("About 7.8% of Ontario postal codes span more than one",
              "dissemination area; \"Return every link\" can give a",
              "record more than one output row.")),
      tags$p(class = "text-muted small",
        sprintf("Correspondence vintage: %s (latest)", latest_da_vintage)),
      actionButton("run_join", "Join", class = "btn-primary w-100 mb-1"),
      tags$div(class = "opcc-section-title", "Downloads"),
      uiOutput("downloads_ui")
    ),
    bslib::navset_tab(
      id = "output_tab",
      bslib::nav_panel(
        "Data table",
        DT::dataTableOutput("joined_table")
      ),
      bslib::nav_panel(
        "Map",
        leaflet::leafletOutput("da_map", height = "calc(100vh - 160px)")
      )
    )
  )
)

server <- function(input, output, session) {

  records_rv <- reactiveVal(NULL)
  joined_rv <- reactiveVal(NULL)
  join_meta_rv <- reactiveVal(NULL)
  postal_points_rv <- reactiveVal(NULL)
  da_matched_rv <- reactiveVal(NULL)
  phu_rv <- reactiveVal(load_local_phu())
  correspondence_rv <- reactiveVal(NULL)
  centroids_rv <- reactiveVal(NULL)
  request_counter <- 0L
  task_state <- list(current_id = NULL, running_id = NULL, pending = NULL)

  invoke_da_request <- function(request) {
    ensure_async_plan()
    da_task$invoke(request)
  }

  observeEvent(input$input_file, {
    req(input$input_file)
    task_state <<- OPCC:::.da_task_transition(task_state, "invalidate")
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
      guess <- OPCC:::.detect_postal_column(records)
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
      typed_codes <- OPCC:::.parse_postal_text(input$postcode_text)
      if (length(typed_codes) == 0L) {
        show_status_popup("warning", "Missing input",
          tags$p("Enter at least one postal code, one per line."))
        return()
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
      OPCC:::.postal_da_join(records, postal_col, correspondence,
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
          OPCC:::.load_postal_centroids()
        }),
        error = function(e) NULL
      )
      if (!is.null(centroids)) centroids_rv(centroids)
    }
    points <- if (is.null(centroids)) NULL else
      OPCC:::.filter_postal_centroids(centroids, input_codes)
    if (!is.null(points) && nrow(points) > 0L) {
      postal_points_rv(points)
    } else {
      postal_points_rv(NULL)
    }
    dauid_values <- result$joined[[result$dauid_col]]
    dauids <- unique(dauid_values[!is.na(dauid_values)])
    n_points <- if (is.null(points)) 0L else nrow(points)
    if (length(dauids) > 0L) {
      request_counter <<- request_counter + 1L
      request_id <- request_counter
      show_status_popup("success", "Join complete",
        tags$p(join_status_text(join_meta_rv(), nrow(result$joined))),
        tags$p(sprintf(
          "%s dissemination area(s) matched; %s postal code point(s) available.",
          format(length(dauids), big.mark = ","),
          format(n_points, big.mark = ","))),
        tags$p(sprintf("Correspondence vintage: %s (latest).", latest_da_vintage)),
        tags$p(class = "text-muted small", "Drawing the map now."))
      task_state <<- OPCC:::.da_task_transition(
        task_state, "join", list(id = request_id, dauids = dauids))
      if (!is.null(task_state$invoke)) {
        request <- task_state$invoke
        task_state$invoke <<- NULL
        invoke_da_request(request)
      }
    } else {
      task_state <<- OPCC:::.da_task_transition(task_state, "invalidate")
      show_status_popup("warning", "Join complete - nothing to draw",
        tags$p(join_status_text(join_meta_rv(), nrow(result$joined))),
        tags$p(sprintf("Correspondence vintage: %s (latest)", latest_da_vintage)),
        tags$p("No matched dissemination areas to draw on the map."))
    }
  })

  output$joined_table <- DT::renderDataTable({
    joined <- joined_rv()
    req(joined)
    joined
  }, rownames = FALSE, options = list(scrollX = TRUE, pageLength = 25))

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
      sf_points <- OPCC:::.postal_points_sf(points, joined)
      OPCC:::.write_postal_points_shapefile(sf_points, file)
    }
  )

  output$dl_script <- downloadHandler(
    filename = function() "reproduce.R",
    content = function(file) {
      meta <- join_meta_rv()
      req(meta)
      if (identical(meta$mode, "text")) {
        script <- OPCC:::.render_opcc_reproducer_script(
          input_file = NULL, postal_col = "postal_code", output_dir = ".",
          vintage = meta$vintage,
          all_links = identical(input$all_links, "all"),
          codes = unique(meta$typed_codes)
        )
      } else {
        req(input$input_file, input$postal_col)
        script <- OPCC:::.render_opcc_reproducer_script(
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

  da_task <- shiny::ExtendedTask$new(function(request) {
    promises::future_promise({
      loadNamespace("sf")
      tolerance <- da_simplify_tolerance
      rds <- file.path(
        tools::R_user_dir("OPCC", "cache"), "shiny-app",
        sprintf("opcc-da-on-2021-simplified-%sm.rds", tolerance)
      )
      if (!file.exists(rds)) {
        paths <- OPCC::download_da_boundaries()
        da_sf <- sf::st_read(paths$da, quiet = TRUE)
        da_sf <- da_sf[da_sf$PRUID == "35", ]
        da_sf <- sf::st_transform(da_sf, 3347)
        da_sf <- sf::st_simplify(da_sf, preserveTopology = FALSE,
                                 dTolerance = tolerance)
        da_sf <- sf::st_transform(da_sf, 4326)
        dir.create(dirname(rds), recursive = TRUE, showWarnings = FALSE)
        saveRDS(da_sf, rds)
      } else {
        da_sf <- readRDS(rds)
      }
      list(id = request$id, da = da_sf[da_sf$DAUID %in% request$dauids, ])
    })
  })

  observeEvent(da_task$status(), {
    s <- da_task$status()
    if (!s %in% c("success", "error")) {
      return()
    }
    finished_id <- task_state$running_id
    task_state <<- OPCC:::.da_task_transition(task_state, "finished")
    accept <- isTRUE(task_state$accept)
    next_request <- task_state$invoke
    task_state$invoke <<- NULL
    if (s == "success") {
      task_result <- da_task$result()
      accept <- accept && identical(task_result$id, finished_id)
      da <- task_result$da
      if (!accept) {
        if (!is.null(next_request)) invoke_da_request(next_request)
        return()
      }
      da_matched_rv(da)
      tryCatch(
        updateTabsetPanel("output_tab", selected = "Map", session = session),
        error = function(e) invisible(NULL)
      )
      meta <- join_meta_rv()
      points <- postal_points_rv()
      n_points <- if (is.null(points)) 0L else nrow(points)
      unmatched_note <- if (!is.null(meta) && length(meta$unmatched) > 0L) {
        sprintf(" %s postal code(s) had no DA and are not drawn as polygons.",
                length(meta$unmatched))
      } else {
        ""
      }
      show_status_popup("success", "Join complete - map ready",
        tags$p(join_status_text(meta, nrow(joined_rv()))),
        tags$p(sprintf(
          "%s dissemination area(s) drawn; %s postal code point(s) on the map.%s",
          format(nrow(da), big.mark = ","),
          format(n_points, big.mark = ","),
          unmatched_note)),
        tags$p(sprintf("Correspondence vintage: %s (latest).", meta$vintage)),
        tags$p(class = "text-muted small",
          paste("The StatCan 2021 DA boundary file and the OPCC postal",
                "centroid file are each downloaded once, checksum-verified,",
                "and reused from the local cache.")))
    } else {
      if (accept) {
        da_matched_rv(NULL)
        show_status_popup("error", "Boundary load failed",
          tags$p(conditionMessage(da_task$error())))
      }
    }
    if (!is.null(next_request)) invoke_da_request(next_request)
  })

  output$da_map <- leaflet::renderLeaflet({
    da <- da_matched_rv()
    joined <- joined_rv()
    req(da, joined, nrow(da) > 0L)
    build_da_map(da, joined, postal_points_rv(), phu_rv())
  })
}

shiny::shinyApp(ui, server)
