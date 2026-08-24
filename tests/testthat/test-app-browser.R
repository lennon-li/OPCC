test_that("installed app joins typed codes and renders the Leaflet map", {
  skip_on_cran()
  skip_if(Sys.getenv("OPCC_RUN_BROWSER_TESTS") != "true",
          "Set OPCC_RUN_BROWSER_TESTS=true for the installed-app browser test")
  runtime <- c("shiny", "bslib", "DT", "leaflet", "htmlwidgets", "sf",
               "chromote", "processx", "httpuv")
  for (pkg in runtime) skip_if_not_installed(pkg)

  chrome <- tryCatch(chromote::find_chrome(), error = function(e) "")
  skip_if(!nzchar(chrome) || !file.exists(chrome),
          "Chrome/Chromium is unavailable to chromote")

  network_ready <- function(url) {
    connection <- tryCatch(suppressWarnings(base::url(url, open = "rb")),
                           error = function(e) NULL)
    if (is.null(connection)) return(FALSE)
    close(connection)
    TRUE
  }
  skip_if(!network_ready("https://raw.githubusercontent.com"),
          "GitHub release host is unavailable")
  skip_if(!network_ready("https://www12.statcan.gc.ca"),
          "Statistics Canada boundary host is unavailable")

  browser_lib <- Sys.getenv("OPCC_BROWSER_TEST_LIB")
  skip_if(!nzchar(browser_lib),
          "OPCC_BROWSER_TEST_LIB must name a library containing this build")
  package_dir <- file.path(browser_lib, "OPCC")
  expect_true(dir.exists(package_dir),
              info = "OPCC_BROWSER_TEST_LIB does not contain OPCC")

  timeout_value <- function(name, default) {
    value <- suppressWarnings(as.numeric(Sys.getenv(name, default)))
    if (!is.finite(value) || value <= 0) default else value
  }
  startup_timeout <- timeout_value("OPCC_BROWSER_STARTUP_TIMEOUT", 60)
  join_timeout <- timeout_value("OPCC_BROWSER_JOIN_TIMEOUT", 900)
  child_libraries <- unique(c(normalizePath(browser_lib), .libPaths()))
  child_library_expression <- paste(
    encodeString(child_libraries, quote = '"'), collapse = ", "
  )

  started <- FALSE
  startup_output <- character()
  for (attempt in seq_len(3L)) {
    port <- httpuv::randomPort(host = "127.0.0.1")
    expression <- sprintf(
      paste0(
        ".libPaths(c(%s)); ",
        "OPCC::run_app(host='127.0.0.1', port=%d, launch.browser=FALSE)"
      ),
      child_library_expression, port
    )
    app <- processx::process$new(
      file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e", expression),
      stdout = "|", stderr = "2>&1", cleanup = TRUE
    )
    url <- sprintf("http://127.0.0.1:%d", port)
    deadline <- Sys.time() + startup_timeout
    while (Sys.time() < deadline) {
      if (!app$is_alive()) break
      response <- tryCatch(
        suppressWarnings(base::url(url, open = "rb")),
        error = function(e) NULL
      )
      if (!is.null(response)) {
        close(response)
        started <- TRUE
        break
      }
      Sys.sleep(0.25)
    }
    if (started) break
    startup_output <- c(startup_output, app$read_all_output_lines())
    if (app$is_alive()) app$kill()
  }
  if (!started) {
    fail(paste("Installed app did not start:",
               paste(startup_output, collapse = "\n")))
    return(invisible(NULL))
  }
  on.exit(if (app$is_alive()) app$kill(), add = TRUE)

  browser <- chromote::ChromoteSession$new()
  on.exit(browser$close(), add = TRUE)
  invisible(browser$Page$navigate(url))

  page_text <- function() {
    browser$Runtime$evaluate("document.body.innerText")$result$value
  }
  evaluate <- function(script) {
    invisible(browser$Runtime$evaluate(script))
  }
  wait_until <- function(predicate, timeout = 180) {
    deadline <- Sys.time() + timeout
    while (Sys.time() < deadline) {
      if (isTRUE(predicate())) return(TRUE)
      Sys.sleep(0.5)
    }
    FALSE
  }

  expect_true(wait_until(function() {
    isTRUE(browser$Runtime$evaluate(
      "!!document.querySelector('#postcode_text')"
    )$result$value)
  }, timeout = 20), info = "Typed-code input did not load")

  evaluate(paste0(
    "Shiny.setInputValue('postcode_text',",
    "'M5V 3A8\\nK1A 0B1',{priority:'event'})"
  ))
  Sys.sleep(0.5)
  evaluate("document.querySelector('#run_join').click()")

  expect_true(wait_until(function() {
    text <- page_text()
    grepl("joined rows", text, fixed = TRUE) ||
      grepl("Boundary load failed", text, fixed = TRUE) ||
      grepl("Join failed", text, fixed = TRUE)
  }, timeout = join_timeout), info = "Join did not finish")

  text <- page_text()
  expect_false(grepl("Boundary load failed", text, fixed = TRUE), info = text)
  expect_false(grepl("Join failed", text, fixed = TRUE), info = text)
  expect_match(text, "joined rows", fixed = TRUE)
  table_text <- browser$Runtime$evaluate(
    "document.querySelector('#joined_table').textContent"
  )$result$value
  expect_match(table_text, "M5V 3A8", fixed = TRUE)
  expect_match(table_text, "K1A 0B1", fixed = TRUE)

  evaluate(paste0(
    "[...document.querySelectorAll('[data-value=\\\"Map\\\"]')][0]",
    ".click()"
  ))
  leaflet_ready <- wait_until(function() {
    browser$Runtime$evaluate(paste0(
      "!!document.querySelector('#da_map .leaflet-map-pane')"
    ))$result$value
  }, timeout = 30)

  map_state <- browser$Runtime$evaluate(paste0(
    "JSON.stringify({",
    "container:!!document.querySelector('#da_map'),",
    "leaflet:!!document.querySelector('#da_map .leaflet-map-pane')",
    "})"
  ))$result$value
  expect_true(
    leaflet_ready,
    info = paste("Leaflet map pane did not initialize; state:", map_state,
                 "page:", page_text())
  )
  expect_match(map_state, '"container":true', fixed = TRUE)
  expect_match(map_state, '"leaflet":true', fixed = TRUE)
})
