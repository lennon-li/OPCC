# scripts/sli_validate.R
#
# Validate OPCC Ontario postal centroids against a maintainer-held local
# Statistics Canada PCCF/SLI QA extract.  The script also supports a synthetic
# benchmark mode when no SLI path is supplied, so the pipeline and tests can
# run without restricted input.
#
# Outputs (in --output-dir):
#   validation_report.md
#   validation_ecdf.png
#   validation_hist.png
#   validation_box.png
#   validation_metrics.json
#   validation_manifest.json
#
# USAGE:
#   Rscript scripts/sli_validate.R \
#     --centroid-csv releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz \
#     --centroid-manifest releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json \
#     --sli-csv /restricted/local/sli_2017.csv \
#     --output-dir docs
#
#   Rscript scripts/sli_validate.R \
#     --centroid-csv releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz \
#     --centroid-manifest releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json \
#     --synthetic \
#     --output-dir docs
#
# ASCII-ONLY.  No restricted row-level data is written to the outputs.

library(ggplot2)
library(scales)

# Source shared helper functions from the test directory.
# Resolve the helper relative to this script so the script works from any cwd.
cmd_args <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", cmd_args, value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE)
repo_root <- dirname(dirname(script_path))
helper <- file.path(repo_root, "tests", "testthat", "helper-sli-validation.R")
if (!file.exists(helper)) {
  stop("Helper not found at ", helper)
}
source(helper)

# ---------------------------------------------------------------------------
# Report / manifest / plot helpers
# ---------------------------------------------------------------------------

write_report <- function(metrics, inputs, output_path) {
  mode_label <- if (inputs$synthetic) "synthetic benchmark" else "local SLI/PCCF QA validation"
  input_note <- if (inputs$synthetic) {
    "This run used a synthetic benchmark generated from the public centroid table. It demonstrates the validation pipeline and does not assert empirical accuracy against an official PCCF/SLI extract."
  } else {
    "This run used a maintainer-held, read-only Statistics Canada PCCF/SLI extract. The extract itself is restricted and is not committed, cached, or redistributed."
  }

  overall <- metrics$overall
  by_src <- metrics$by_source

  lines <- c(
    "# OPCC Centroid Validation Report",
    "",
    paste("**Mode:**", mode_label),
    paste("**Centroid artifact:**", inputs$centroid_csv),
    paste("**Centroid manifest:**", inputs$centroid_manifest),
    if (!inputs$synthetic) paste("**SLI/PCCF input:**", inputs$sli_csv) else NULL,
    paste("**Generated:**", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    "",
    "## Inputs and boundary",
    "",
    input_note,
    "",
    "The Statistics Canada Postal Code Conversion File (PCCF) and related",
    "SLI extracts contain Canada Post proprietary information. They are used",
    "only as local, read-only QA material under an explicit maintainer exception.",
    "They are not package inputs, release artifacts, contribution evidence, or",
    "redistributed OPCC content. Public users can reproduce the pipeline, but",
    "empirical comparison against an official extract requires their own",
    "authorised access to that restricted input.",
    "",
    "## Coverage",
    "",
    sprintf("- Open-data distinct postal codes: %s",
            format(metrics$coverage$distinct_open_postal_codes, big.mark = ",")),
    sprintf("- QA distinct postal codes: %s",
            format(metrics$coverage$distinct_sli_postal_codes, big.mark = ",")),
    sprintf("- Matched postal codes: %s",
            format(metrics$coverage$matched_postal_codes, big.mark = ",")),
    sprintf("- Coverage: %.2f %%", metrics$coverage$coverage_pct),
    "",
    "## Spatial accuracy",
    "",
    sprintf("- Matched comparisons: %s",
            format(metrics$joined_n, big.mark = ",")),
    sprintf("- Median distance: %.3f km", overall$median_distance_km),
    sprintf("- Mean distance: %.3f km", overall$mean_distance_km),
    sprintf("- 90th percentile: %.3f km", overall$p90_distance_km),
    sprintf("- 95th percentile: %.3f km", overall$p95_distance_km),
    sprintf("- 99th percentile: %.3f km", overall$p99_distance_km),
    sprintf("- Max distance: %.3f km", overall$max_distance_km),
    "",
    "## Accuracy by centroid source",
    "",
    "| point_source | count | median_km | mean_km | p90_km | p95_km | p99_km | max_km |",
    "| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
  )

  for (i in seq_len(nrow(by_src))) {
    r <- by_src[i, ]
    lines <- c(lines, sprintf(
      "| %s | %s | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f |",
      r$point_source,
      format(r$n, big.mark = ","),
      r$median_distance_km,
      r$mean_distance_km,
      r$p90_distance_km,
      r$p95_distance_km,
      r$p99_distance_km,
      r$max_distance_km
    ))
  }

  lines <- c(lines,
    "",
    "## Visualisations",
    "",
    "All plots are rendered deterministically from the same input set. They",
    "illustrate the validation output and are committed only as documentation.",
    "",
    "### Cumulative accuracy (ECDF)",
    "",
    "![Cumulative accuracy](./validation_ecdf.png)",
    "",
    "### Distribution of deviations under 5 km",
    "",
    "![Deviations under 5 km](./validation_hist.png)",
    "",
    "### Distance variance by source",
    "",
    "![Distance by source](./validation_box.png)",
    "",
    "## Result",
    "",
    if (inputs$synthetic) {
      "This is a synthetic benchmark run. See the metrics JSON and manifest for reproducibility metadata."
    } else {
      "Empirical validation completed against the authorised local QA input. See the metrics JSON and manifest for reproducibility metadata."
    }
  )

  writeLines(lines, output_path)
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  out <- list(
    centroid_csv      = NULL,
    centroid_manifest = NULL,
    sli_csv           = NULL,
    output_dir        = "docs",
    synthetic         = FALSE,
    seed              = 42L
  )
  i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (a == "--centroid-csv") { out$centroid_csv <- args[i + 1]; i <- i + 2
    } else if (a == "--centroid-manifest") { out$centroid_manifest <- args[i + 1]; i <- i + 2
    } else if (a == "--sli-csv") { out$sli_csv <- args[i + 1]; i <- i + 2
    } else if (a == "--output-dir") { out$output_dir <- args[i + 1]; i <- i + 2
    } else if (a == "--seed") { out$seed <- as.integer(args[i + 1]); i <- i + 2
    } else if (a == "--synthetic") { out$synthetic <- TRUE; i <- i + 1
    } else { stop("Unknown argument: ", a) }
  }
  if (is.null(out$centroid_csv) || is.null(out$centroid_manifest)) {
    stop("--centroid-csv and --centroid-manifest are required.")
  }
  if (!out$synthetic && is.null(out$sli_csv)) {
    stop("Either --sli-csv or --synthetic must be supplied.")
  }
  out
}

main <- function() {
  Sys.setenv(LANGUAGE = "en")
  set.seed(42L)

  inputs <- parse_args()
  if (!dir.exists(inputs$output_dir)) {
    dir.create(inputs$output_dir, recursive = TRUE)
  }

  cat("=== sli_validate.R ===\n")
  cat("Centroid artifact:", inputs$centroid_csv, "\n")
  cat("Centroid manifest:", inputs$centroid_manifest, "\n")

  centroids <- sli_read_centroids(inputs$centroid_csv)
  cat("Distinct open centroids:", format(n_distinct(centroids$postal_code), big.mark = ","), "\n")

  if (inputs$synthetic) {
    cat("Mode: synthetic benchmark\n")
    sli <- sli_make_synthetic_qa(centroids, seed = inputs$seed)
  } else {
    cat("Mode: local SLI/PCCF QA input:", inputs$sli_csv, "\n")
    sli <- sli_read_sli(inputs$sli_csv)
  }
  cat("QA rows:", format(nrow(sli), big.mark = ","), "\n")

  metrics <- sli_compute_metrics(centroids, sli)

  joined <- centroids %>%
    inner_join(sli, by = "postal_code", suffix = c("", "_sli")) %>%
    mutate(distance_km = sli_haversine_km(latitude, longitude,
                                          latitude_sli, longitude_sli))

  png(file.path(inputs$output_dir, "validation_ecdf.png"),
      width = 2400, height = 1800, res = 300, type = "cairo")
  p <- ggplot(joined, aes(x = distance_km, colour = point_source)) +
    stat_ecdf(geom = "step", linewidth = 0.8) +
    scale_x_continuous(trans = log1p_trans(),
                       breaks = c(0, 0.01, 0.1, 1, 10, 100, 1000)) +
    coord_cartesian(xlim = c(0, NA)) +
    labs(x = "Distance (km, log1p scale)", y = "Cumulative fraction",
         title = "Cumulative accuracy by centroid source",
         colour = "Centroid source") +
    theme_minimal(base_size = 14) +
    theme(legend.position = "bottom")
  print(p)
  dev.off()

  png(file.path(inputs$output_dir, "validation_hist.png"),
      width = 2400, height = 1800, res = 300, type = "cairo")
  p <- ggplot(joined %>% filter(distance_km < 5),
              aes(x = distance_km, fill = point_source)) +
    geom_histogram(bins = 50, colour = "white") +
    facet_wrap(vars(point_source), ncol = 1, scales = "free_y") +
    labs(x = "Distance (km)", y = "Count",
         title = "Distribution of deviations under 5 km",
         fill = "Centroid source") +
    theme_minimal(base_size = 14) +
    theme(legend.position = "bottom")
  print(p)
  dev.off()

  png(file.path(inputs$output_dir, "validation_box.png"),
      width = 2400, height = 1800, res = 300, type = "cairo")
  p <- ggplot(joined, aes(x = point_source, y = distance_km,
                          fill = point_source)) +
    geom_boxplot(outlier.size = 0.8) +
    scale_y_continuous(trans = log1p_trans()) +
    labs(x = "Centroid source", y = "Distance (km, log1p scale)",
         title = "Distance variance by centroid source",
         fill = "Centroid source") +
    theme_minimal(base_size = 14) +
    theme(legend.position = "bottom")
  print(p)
  dev.off()

  write_report(metrics, inputs, file.path(inputs$output_dir, "validation_report.md"))

  metrics_out <- list(
    mode = if (inputs$synthetic) "synthetic" else "sli_qa",
    overall = metrics$overall,
    by_source = as.data.frame(metrics$by_source),
    coverage = metrics$coverage,
    inputs = list(
      centroid_csv = inputs$centroid_csv,
      centroid_manifest = inputs$centroid_manifest,
      sli_csv = inputs$sli_csv,
      synthetic = inputs$synthetic
    )
  )
  jsonlite::write_json(metrics_out,
                       path = file.path(inputs$output_dir, "validation_metrics.json"),
                       pretty = TRUE, auto_unbox = TRUE)

  report_sha  <- digest::digest(file.path(inputs$output_dir, "validation_report.md"),
                                algo = "sha256", file = TRUE)
  ecdf_sha    <- digest::digest(file.path(inputs$output_dir, "validation_ecdf.png"),
                                algo = "sha256", file = TRUE)
  hist_sha    <- digest::digest(file.path(inputs$output_dir, "validation_hist.png"),
                                algo = "sha256", file = TRUE)
  box_sha     <- digest::digest(file.path(inputs$output_dir, "validation_box.png"),
                                algo = "sha256", file = TRUE)
  metrics_sha <- digest::digest(file.path(inputs$output_dir, "validation_metrics.json"),
                                algo = "sha256", file = TRUE)

  manifest <- list(
    manifest_version = 1L,
    run_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    generator = list(
      script = "scripts/sli_validate.R",
      repo_sha = system("git rev-parse HEAD", intern = TRUE),
      r_version = paste0(R.version$major, ".", R.version$minor)
    ),
    inputs = list(
      centroid_csv = inputs$centroid_csv,
      centroid_manifest = inputs$centroid_manifest,
      centroid_csv_sha256 = digest::digest(inputs$centroid_csv, algo = "sha256", file = TRUE),
      sli_csv = inputs$sli_csv,
      synthetic = inputs$synthetic
    ),
    outputs = list(
      validation_report_md  = list(path = "validation_report.md",  sha256 = report_sha),
      validation_ecdf_png   = list(path = "validation_ecdf.png",   sha256 = ecdf_sha),
      validation_hist_png   = list(path = "validation_hist.png",   sha256 = hist_sha),
      validation_box_png    = list(path = "validation_box.png",    sha256 = box_sha),
      validation_metrics_json = list(path = "validation_metrics.json", sha256 = metrics_sha)
    ),
    restricted_input_note = paste(
      "No SLI/PCCF rows, coordinates, or screenshots are committed.",
      "If a local SLI/PCCF input was used, only permitted identity/hash metadata",
      "and aggregate statistics appear above.",
      sep = " "
    )
  )

  jsonlite::write_json(manifest,
                       path = file.path(inputs$output_dir, "validation_manifest.json"),
                       pretty = TRUE, auto_unbox = TRUE)

  cat("Outputs written to:", inputs$output_dir, "\n")
  cat("=== Done ===\n")
}

if (sys.nframe() == 0L) main()
