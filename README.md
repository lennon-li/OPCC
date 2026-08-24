# OPCC

[![R package check](https://github.com/lennon-li/OPCC/actions/workflows/r-package-check.yml/badge.svg)](https://github.com/lennon-li/OPCC/actions/workflows/r-package-check.yml)

**Open Postal Code Correspondence** -- an open, reproducible R package for
linking Ontario postal codes to Statistics Canada 2021 census geographies
(Dissemination Blocks and Dissemination Areas).

OPCC does not redistribute Canada Post, PCCF, or PCCF+ data. Its evidence
unit is an observed postal association from redistributable public sources.

## Install

Requires R >= 4.1.

```r
install.packages("pak")
pak::pak("lennon-li/OPCC")
```

## Quick start

Artifacts are downloaded, checksum-verified, and cached automatically on
first use.

```r
library(OPCC)

# Best DA link for a postal code
pc_to_geo("M5V 3A8", level = "DA", all_links = FALSE)

# Multiple postal codes at once
pc_to_geo(c("M5V 3A8", "K1A 0A6"), level = "DA", all_links = FALSE)

# Join census geographies to your own data
da <- get_da_correspondence(vintage = "2026-07-20")
my_data <- data.frame(postal_code = c("M5V 3A8", "K1A 0A6"),
                      stringsAsFactors = FALSE)
merge(my_data, da[da$best_link, c("postal_code", "DAUID", "allocation_weight")],
      by = "postal_code", all.x = TRUE)

# Verify artifact integrity
validate_release(vintage = "2026-07-20", level = "DA")
```

Full guide with `dplyr` joins, offline use, DB lookups, point observations,
and local source import:

```r
vignette("using-opcc", package = "OPCC")
```

## Interactive app

Upload a CSV, pick its postal-code column, and join it to the
postal-code-to-DA correspondence: view the joined table, draw the matched
dissemination areas on a map, and download the joined CSV, the map as HTML,
and an R script that reproduces both.

```r
run_app()
```

Requires `shiny`, `bslib`, `DT`, `leaflet`, `htmlwidgets`, and `sf`.

The app keeps the roughly 200 MB Statistics Canada boundary download and its
extracted build inputs in a unique session directory and deletes them when the
session ends. By default, the simplified map artifact is session-only too, so
each new session downloads and rebuilds it. A user or server operator can opt
in to reusing only that derived RDS by setting either
`options(OPCC.shiny_da_cache_dir = "/managed/path")` before `run_app()`, or the
`OPCC_SHINY_DA_CACHE_DIR` environment variable. The R option takes precedence.
OPCC never places the raw archive or extraction in that managed directory.
Shared-cache builds use an owner lock. A lock owned by a live process on the
same host is never expired based on age; cross-host locks carry a build-phase
heartbeat and are recoverable after two hours without progress. If a live
builder outlasts a session's wait, that session falls back to its private raw
cache rather than overwriting the shared artifact.

## Reproduce from scratch

Rebuild every artifact from raw Statistics Canada sources using package
functions only (requires `sf`, `dplyr`, `readr`):

```r
nar_dir <- download_nar()
geonames_txt <- download_geonames()
bounds <- download_census_boundaries()
gaf_csv <- download_gaf()

centroids_csv <- build_centroids(nar_dir, geonames_txt)
rollup_csv <- build_db_assignment(centroids_csv, bounds$province, bounds$db, gaf_csv)
m2_csv <- build_m2(nar_dir, bounds$db, gaf_csv, rollup_csv)

db <- utils::read.csv(m2_csv, stringsAsFactors = FALSE)
da <- aggregate_da_correspondence(db)
```

Each step messages its progress. See Part 2 of the vignette for detail.

## Validation

M5 DA correspondence was benchmarked against an authorised PCCF-derived
Ontario DA export: 99.46% any-link agreement, 95.65% best-link containment,
93.92% pair F1 across 280,649 comparable postal codes. See
[docs/validation-summary.md](docs/validation-summary.md).

Agreement with that benchmark does not make OPCC authoritative, certified, or
a drop-in replacement for Canada Post, PCCF, or PCCF+ products. The comparison
is DA-level only, and the benchmark's vintage predates the OPCC release it was
compared against. The evidence unit remains an observed postal association,
and unmatched postal codes stay explicit rather than being filled in.

## Community

Contribute only open, redistributable evidence. See `CONTRIBUTING.md`,
`GOVERNANCE.md`, `SECURITY.md`, and `CITATION.cff`.

To report a bug, [open an issue](https://github.com/lennon-li/OPCC/issues/new/choose)
with your OPCC and R versions, a minimal reproducible example, the expected and
observed results, and any relevant release vintage or source identifier. Do not
include Canada Post, PCCF, PCCF+, or other restricted data.

OPCC is not affiliated with Canada Post or Statistics Canada.
