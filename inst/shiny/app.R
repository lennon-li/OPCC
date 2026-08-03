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

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

codes_per_da <- function(joined) {
  rows <- !is.na(joined$DAUID)
  if (!any(rows)) {
    return(list())
  }
  split(joined$opcc_postal_code[rows], joined$DAUID[rows])
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

build_da_map <- function(da_matched, joined, points = NULL) {
  codes_list <- codes_per_da(joined)
  bounds <- sf::st_bbox(da_matched)
  map <- leaflet::leaflet() |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) |>
    leaflet::addPolygons(
      data = da_matched,
      fillColor = da_fill_color, fillOpacity = 0.4,
      color = da_border_color, weight = 1,
      popup = da_popup(da_matched, codes_list),
      group = "Matched dissemination areas"
    ) |>
    leaflet::fitBounds(bounds[["xmin"]], bounds[["ymin"]],
                       bounds[["xmax"]], bounds[["ymax"]])
  overlay_groups <- "Matched dissemination areas"
  if (!is.null(points) && nrow(points) > 0L) {
    map <- leaflet::addCircleMarkers(
      map,
      data = points,
      lng = ~longitude, lat = ~latitude,
      radius = 3, color = "#e4572e", fillOpacity = 0.9, weight = 1,
      popup = ~paste0("<b>", html_escape(postal_code), "</b> (",
                      html_escape(point_source), ", ",
                      html_escape(point_method), ")"),
      group = "Supplementary postal points (GeoNames)"
    )
    overlay_groups <- c(overlay_groups, "Supplementary postal points (GeoNames)")
  }
  legend_colors <- da_fill_color
  legend_labels <- "Matched dissemination area"
  if (!is.null(points) && nrow(points) > 0L) {
    legend_colors <- c(legend_colors, "#e4572e")
    legend_labels <- c(legend_labels, "Supplementary postal point")
  }
  map <- leaflet::addLegend(
    map, position = "bottomleft",
    colors = legend_colors, labels = legend_labels, title = NULL
  )
  if (length(overlay_groups) > 1L) {
    map <- leaflet::addLayersControl(
      map,
      overlayGroups = overlay_groups,
      options = leaflet::layersControlOptions(collapsed = FALSE)
    )
  }
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

vintage_choices <- rev(OPCC::list_vintages("DA"))

ui <- bslib::page_fillable(
  window_title = "OPCC",
  theme = bslib::bs_theme(version = 5, primary = da_fill_color),
  tags$div(
    class = "top-nav",
    bslib::navset_tab(
      bslib::nav_panel(
        "Data",
        bslib::layout_sidebar(
          sidebar = bslib::sidebar(
            width = 320,
            tags$strong("OPCC - postal code to dissemination area"),
            fileInput("input_file", "Upload a CSV",
              accept = c(".csv", "text/csv"),
              buttonLabel = "Browse...",
              placeholder = "CSV with a postal-code column"),
            uiOutput("postal_col_ui"),
            radioButtons("all_links", "Multiple dissemination areas",
              choices = c("Keep one best link per postal code" = "best",
                          "Return every link" = "all"),
              selected = "best"),
            tags$p(class = "text-muted",
              paste("About 7.8% of Ontario postal codes span more than one",
                    "dissemination area; \"Return every link\" can give a",
                    "record more than one output row.")),
            selectInput("vintage", "Correspondence vintage",
              choices = vintage_choices),
            actionButton("run_join", "Join", class = "btn-primary w-100 mb-1"),
            uiOutput("join_status"),
            tags$hr(),
            tags$strong("Downloads"),
            uiOutput("downloads_ui")
          ),
          DT::dataTableOutput("joined_table")
        )
      ),
      bslib::nav_panel(
        "Map",
        bslib::layout_sidebar(
          sidebar = bslib::sidebar(
            width = 320,
            uiOutput("map_info"),
            actionButton("draw_map", "Draw map",
              class = "btn-primary w-100 mb-1"),
            tags$p(class = "text-muted",
              paste("First use downloads the ~200 MB StatCan 2021",
                    "dissemination-area boundary file, simplifies the",
                    "Ontario subset once, and caches both.")),
            uiOutput("map_status")
          ),
          leaflet::leafletOutput("da_map", height = "calc(100vh - 90px)")
        )
      )
    )
  )
)

server <- function(input, output, session) {

  records_rv <- reactiveVal(NULL)
  joined_rv <- reactiveVal(NULL)
  join_meta_rv <- reactiveVal(NULL)
  joined_points_rv <- reactiveVal(NULL)
  da_matched_rv <- reactiveVal(NULL)
  join_status_msg <- reactiveVal(NULL)
  map_status_msg <- reactiveVal(NULL)

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
      join_status_msg(sprintf("Could not read the file: %s",
                              conditionMessage(records)))
      return()
    }
    records_rv(records)
    joined_rv(NULL)
    join_meta_rv(NULL)
    joined_points_rv(NULL)
    da_matched_rv(NULL)
    join_status_msg(NULL)
  })

  output$postal_col_ui <- renderUI({
    records <- records_rv()
    if (is.null(records)) {
      return(tags$p(class = "text-muted",
                    "Upload a CSV to choose its postal code column."))
    }
    guess <- OPCC:::.detect_postal_column(records)
    selectInput("postal_col", "Postal code column",
      choices = colnames(records),
      selected = if (!is.na(guess)) guess)
  })

  output$join_status <- renderUI({
    msg <- join_status_msg()
    req(msg)
    tags$p(class = "text-muted", msg)
  })

  observeEvent(input$run_join, {
    records <- records_rv()
    req(records, input$postal_col, input$vintage)
    all_links <- identical(input$all_links, "all")
    correspondence <- tryCatch(
      shiny::withProgress(message = "Fetching DA correspondence", value = 0.3, {
        OPCC::get_da_correspondence(vintage = input$vintage)
      }),
      error = function(e) e
    )
    if (inherits(correspondence, "error")) {
      joined_rv(NULL)
      join_meta_rv(NULL)
      join_status_msg(sprintf("Join failed: %s", conditionMessage(correspondence)))
      return()
    }
    result <- tryCatch(
      OPCC:::.postal_da_join(records, input$postal_col, correspondence,
                             all_links = all_links),
      error = function(e) e
    )
    if (inherits(result, "error")) {
      joined_rv(NULL)
      join_meta_rv(NULL)
      join_status_msg(sprintf("Join failed: %s", conditionMessage(result)))
      return()
    }
    joined_rv(result$joined)
    join_meta_rv(list(
      vintage = input$vintage,
      all_links = all_links,
      unmatched = result$unmatched,
      invalid_count = result$invalid_count
    ))
    da_matched_rv(NULL)
    status <- sprintf(
      "%s input row(s) in, %s row(s) out, %s postal code(s) unmatched, %s invalid value(s).",
      format(result$n_input, big.mark = ","),
      format(nrow(result$joined), big.mark = ","),
      format(length(result$unmatched), big.mark = ","),
      format(result$invalid_count, big.mark = ","))
    if (length(result$unmatched) > 0L) {
      status <- paste(status, sprintf("Unmatched: %s",
        paste(head(result$unmatched, 8L), collapse = ", ")))
    }
    matched_codes <- unique(result$joined$opcc_postal_code[
      !is.na(result$joined$DAUID)])
    if (length(matched_codes) > 0L) {
      points <- tryCatch(OPCC::pc_to_point(matched_codes),
                         error = function(e) NULL)
      if (!is.null(points) && nrow(points) > 0L) {
        joined_points_rv(points)
      } else {
        joined_points_rv(NULL)
      }
    } else {
      joined_points_rv(NULL)
    }
    join_status_msg(status)
  })

  output$joined_table <- DT::renderDataTable({
    joined <- joined_rv()
    req(joined)
    joined
  }, rownames = FALSE, options = list(scrollX = TRUE, pageLength = 25))

  output$downloads_ui <- renderUI({
    joined_ready <- !is.null(joined_rv()) && nrow(joined_rv()) > 0L
    map_ready <- joined_ready && !is.null(da_matched_rv()) &&
      nrow(da_matched_rv()) > 0L
    download_or_disabled(list(
      list(id = "dl_csv", label = "opcc_postal_da.csv", ready = joined_ready),
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

  output$dl_script <- downloadHandler(
    filename = function() "reproduce.R",
    content = function(file) {
      req(input$input_file, input$postal_col, input$vintage)
      writeLines(
        OPCC:::.render_opcc_reproducer_script(
          input$input_file$name, input$postal_col, ".",
          input$vintage, all_links = identical(input$all_links, "all")
        ),
        file
      )
    }
  )

  output$dl_map <- downloadHandler(
    filename = function() "opcc_map.html",
    content = function(file) {
      da <- da_matched_rv()
      joined <- joined_rv()
      req(da, joined, nrow(da) > 0L)
      map <- build_da_map(da, joined, joined_points_rv())
      htmlwidgets::saveWidget(map, file, selfcontained = TRUE)
    }
  )

  da_task <- shiny::ExtendedTask$new(function(dauids) {
    promises::future_promise({
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
      da_sf[da_sf$DAUID %in% dauids, ]
    })
  })

  output$map_info <- renderUI({
    joined <- joined_rv()
    if (is.null(joined)) {
      return(tags$p(class = "text-muted",
                    "Run a join on the Data tab first."))
    }
    dauids <- unique(joined$DAUID[!is.na(joined$DAUID)])
    tags$p(class = "text-muted",
      sprintf("%s matched dissemination area(s) in the current join.",
              format(length(dauids), big.mark = ",")))
  })

  output$map_status <- renderUI({
    msg <- map_status_msg()
    req(msg)
    tags$p(class = "text-muted", msg)
  })

  observeEvent(input$draw_map, {
    joined <- joined_rv()
    if (is.null(joined)) {
      map_status_msg("Run a join on the Data tab first.")
      return()
    }
    dauids <- unique(joined$DAUID[!is.na(joined$DAUID)])
    if (length(dauids) == 0L) {
      map_status_msg("No matched dissemination areas to draw.")
      return()
    }
    if (identical(da_task$status(), "running")) {
      return()
    }
    ensure_async_plan()
    da_task$invoke(dauids)
    map_status_msg(sprintf(
      "Loading dissemination-area boundaries for %s area(s); first use downloads ~200 MB.",
      format(length(dauids), big.mark = ",")))
  })

  observeEvent(da_task$status(), {
    s <- da_task$status()
    if (!s %in% c("success", "error")) {
      return()
    }
    if (s == "success") {
      da <- da_task$result()
      da_matched_rv(da)
      matched_meta <- join_meta_rv()
      unmatched_note <- if (!is.null(matched_meta) &&
                            length(matched_meta$unmatched) > 0L) {
        sprintf(" %s postal code(s) had no DA and are not drawn.",
                length(matched_meta$unmatched))
      } else {
        ""
      }
      map_status_msg(sprintf("%s dissemination area(s) drawn.%s",
                             format(nrow(da), big.mark = ","), unmatched_note))
    } else {
      da_matched_rv(NULL)
      map_status_msg(sprintf("Boundary load failed: %s",
                             conditionMessage(da_task$error())))
    }
  })

  output$da_map <- leaflet::renderLeaflet({
    da <- da_matched_rv()
    joined <- joined_rv()
    req(da, joined, nrow(da) > 0L)
    build_da_map(da, joined, joined_points_rv())
  })
}

shiny::shinyApp(ui, server)
