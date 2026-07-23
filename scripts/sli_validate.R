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
# All committed outputs are deterministic: no wall-clock time is embedded.
# Reproducibility is anchored to the producer revision, input manifest hashes,
# and an explicit seed.
#
# USAGE:
#   Rscript scripts/sli_validate.R \
#     --centroid-csv releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz \
#     --centroid-manifest releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json \
#     --producer-ref <full-commit-SHA> \
#     --sli-csv /restricted/local/sli_2017.csv \
#     --sli-label "PCCF SLI 2017 QA" \
#     --output-dir docs
#
#   Rscript scripts/sli_validate.R \
#     --centroid-csv releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz \
#     --centroid-manifest releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json \
#     --producer-ref <full-commit-SHA> \
#     --synthetic \
#     --output-dir docs
#
# ASCII-ONLY.  No restricted row-level data is written to the outputs.

library(ggplot2)
library(scales)
library(dplyr)
library(digest)
library(jsonlite)

# Resolve the validation engine relative to this script so it works from any
# working directory.
cmd_args <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", cmd_args, value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE)
repo_root <- dirname(dirname(script_path))
helper <- file.path(repo_root, "R", "validation-metrics.R")
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
    paste("**Generator commit:**", inputs$build_ref),
    if (!inputs$synthetic) paste("**SLI/PCCF input label:**", inputs$sli_label) else NULL,
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
    producer_ref      = NULL,
    sli_csv           = NULL,
    sli_label         = NULL,
    output_dir        = NULL,
    synthetic         = FALSE,
    seed              = 42L
  )
  i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (a == "--centroid-csv") { out$centroid_csv <- args[i + 1]; i <- i + 2
    } else if (a == "--centroid-manifest") { out$centroid_manifest <- args[i + 1]; i <- i + 2
    } else if (a == "--producer-ref") { out$producer_ref <- args[i + 1]; i <- i + 2
    } else if (a == "--sli-csv") { out$sli_csv <- args[i + 1]; i <- i + 2
    } else if (a == "--sli-label") { out$sli_label <- args[i + 1]; i <- i + 2
    } else if (a == "--output-dir") { out$output_dir <- args[i + 1]; i <- i + 2
    } else if (a == "--seed") { out$seed <- as.integer(args[i + 1]); i <- i + 2
    } else if (a == "--synthetic") { out$synthetic <- TRUE; i <- i + 1
    } else { stop("Unknown argument: ", a) }
  }
  if (is.null(out$centroid_csv) || is.null(out$centroid_manifest)) {
    stop("--centroid-csv and --centroid-manifest are required.")
  }
  if (is.null(out$producer_ref)) {
    stop("--producer-ref is required.")
  }
  if (is.null(out$output_dir)) {
    stop("--output-dir is required.")
  }
  if (out$synthetic && !is.null(out$sli_csv)) {
    stop("--synthetic and --sli-csv are mutually exclusive.")
  }
  if (!out$synthetic && is.null(out$sli_csv)) {
    stop("Either --sli-csv or --synthetic must be supplied.")
  }
  if (!out$synthetic && is.null(out$sli_label)) {
    stop("--sli-label is required when using --sli-csv.")
  }
  out
}

main <- function() {
  Sys.setenv(LANGUAGE = "en")

  inputs <- parse_args()
  sli_validate_output_directory(
    inputs$output_dir,
    repo_root,
    inputs$synthetic
  )
  if (!dir.exists(inputs$output_dir)) {
    dir.create(inputs$output_dir, recursive = TRUE)
  }

  cat("=== sli_validate.R ===\n")
  cat("Centroid artifact:", inputs$centroid_csv, "\n")
  cat("Centroid manifest:", inputs$centroid_manifest, "\n")

  if (!file.exists(inputs$centroid_manifest)) {
    stop("Centroid manifest not found: ", inputs$centroid_manifest)
  }
  parent_manifest <- jsonlite::read_json(inputs$centroid_manifest)
  parent_manifest_sha256 <- digest::digest(inputs$centroid_manifest,
                                           algo = "sha256", file = TRUE)

  # Validate the parent M1 artifact before any metrics are computed.
  sli_verify_m1_artifact(inputs$centroid_csv, parent_manifest)
  cat("Parent M1 artifact verified against manifest.\n")

  inputs$build_ref <- sli_validate_producer_ref(
    inputs$producer_ref,
    c("scripts/sli_validate.R")
  )
  cat("Producer revision:", inputs$build_ref, "\n")

  set.seed(inputs$seed)

  centroids <- sli_read_centroids(inputs$centroid_csv)
  cat("Distinct open centroids:", format(dplyr::n_distinct(centroids$postal_code), big.mark = ","), "\n")

  if (inputs$synthetic) {
    cat("Mode: synthetic benchmark\n")
    sli <- sli_make_synthetic_qa(centroids, seed = inputs$seed)
  } else {
    cat("Mode: local SLI/PCCF QA input\n")
    cat("SLI label:", inputs$sli_label, "\n")
    sli <- sli_read_sli(inputs$sli_csv)
  }
  cat("QA rows:", format(nrow(sli), big.mark = ","), "\n")

  metrics <- sli_compute_metrics(centroids, sli)

  joined <- sli_compute_point_distances(centroids, sli)

  grDevices::png(file.path(inputs$output_dir, "validation_ecdf.png"),
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
  grDevices::dev.off()

  grDevices::png(file.path(inputs$output_dir, "validation_hist.png"),
                 width = 2400, height = 1800, res = 300, type = "cairo")
  p <- ggplot(joined %>% dplyr::filter(distance_km < 5),
               aes(x = distance_km, fill = point_source)) +
    geom_histogram(bins = 50, colour = "white") +
    facet_wrap(vars(point_source), ncol = 1, scales = "free_y") +
    labs(x = "Distance (km)", y = "Count",
         title = "Distribution of deviations under 5 km",
         fill = "Centroid source") +
    theme_minimal(base_size = 14) +
    theme(legend.position = "bottom")
  print(p)
  grDevices::dev.off()

  grDevices::png(file.path(inputs$output_dir, "validation_box.png"),
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
  grDevices::dev.off()

  write_report(metrics, inputs, file.path(inputs$output_dir, "validation_report.md"))

  restricted_input <- if (inputs$synthetic) {
    list(recorded = FALSE, reason = "synthetic benchmark")
  } else {
    list(
      recorded = TRUE,
      label = inputs$sli_label,
      hash = digest::digest(inputs$sli_csv, algo = "sha256", file = TRUE)
    )
  }

  metrics_out <- list(
    mode = if (inputs$synthetic) "synthetic" else "sli_qa",
    build_ref = inputs$build_ref,
    overall = metrics$overall,
    by_source = as.data.frame(metrics$by_source),
    coverage = metrics$coverage,
    inputs = list(
      centroid_csv = inputs$centroid_csv,
      centroid_manifest = inputs$centroid_manifest,
      parent_manifest_sha256 = parent_manifest_sha256,
      centroid_csv_sha256 = parent_manifest$artifact$csv_sha256,
      centroid_gz_sha256 = parent_manifest$artifact$gz_sha256,
      synthetic = inputs$synthetic
    ),
    restricted_input = restricted_input
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
    build_ref = inputs$build_ref,
    generator = list(
      script = "scripts/sli_validate.R",
      repo_sha = inputs$build_ref,
      r_version = paste0(R.version$major, ".", R.version$minor)
    ),
    inputs = list(
      centroid_csv = inputs$centroid_csv,
      centroid_manifest = inputs$centroid_manifest,
      parent_manifest_sha256 = parent_manifest_sha256,
      centroid_csv_sha256 = parent_manifest$artifact$csv_sha256,
      centroid_gz_sha256 = parent_manifest$artifact$gz_sha256,
      sli_label = if (inputs$synthetic) NULL else inputs$sli_label,
      sli_hash = if (inputs$synthetic) NULL else restricted_input$hash,
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
