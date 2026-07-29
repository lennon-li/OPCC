# M2 Reproduction Guide

M2 builds a NAR-only correspondence from observed address evidence. It does not
reconstruct Canada Post assignments and does not use restricted Ontario postal
data or licensed PCCF data.

## Package functions (recommended)

The M2 build is available as a transparent package function. No source checkout
or manual download is needed:

```r
library(OPCC)

# Step 1: Download all public inputs (cached automatically)
nar_dir <- download_nar()
geonames_txt <- download_geonames()
bounds <- download_census_boundaries()
gaf_csv <- download_gaf()

# Step 2: Build centroids and DB assignment (M1 prerequisites)
centroids_csv <- build_centroids(nar_dir, geonames_txt)
rollup_csv <- build_db_assignment(centroids_csv, bounds$province, bounds$db, gaf_csv)

# Step 3: Build M2 correspondence
m2_csv <- build_m2(nar_dir, bounds$db, gaf_csv, rollup_csv)

# Step 4: Reproduce DA roll-up (M5)
db <- utils::read.csv(m2_csv, stringsAsFactors = FALSE)
da <- aggregate_da_correspondence(db)
```

Each function messages its progress. See `vignette("using-opcc", package =
"OPCC")` for the full guide.

## Inputs (script-based)

Run the M1 preparation first so these relative paths exist:

- `.scratch/m1_nar/Addresses/Address_35_*.csv`
- `.scratch/m1_nar/Locations/Location_35_*.csv`
- `.scratch/shp/ldb_000b21a_e.shp`
- `.scratch/gaf/2021_92-151_X.csv`

The M2 script never downloads data. Raw inputs are scratch data and must not be
committed.

## Build

From the repository root:

```bash
Rscript scripts/m2_build_correspondence.R
```

Outputs are written under `.scratch/m2/`:

- `m2_correspondence.csv`
- `m2_manifest.json`

## Exact rebuild and verification sequence

Use the producer revision recorded in the published manifest, not the moving
tip of `main`. The following sequence rebuilds the uncompressed M2
correspondence from the source files named and SHA-256-pinned in that manifest.
It must run in a disposable worktree because the required raw inputs are large
and must remain untracked.

```bash
git clone https://github.com/lennon-li/OPCC.git opcc-m2-rebuild
cd opcc-m2-rebuild
git checkout 16eade1a12cdf33d1cf596a2ee1cc049056317c1

# Place the NAR, 2021 DB boundary, and GAF files at the exact .scratch paths
# listed in releases/m2/2026-06-26/m2_manifest.json, after matching each
# input's recorded SHA-256.
Rscript scripts/m2_build_correspondence.R

# Verify the regenerated uncompressed correspondence bytes.
Rscript -e 'stopifnot(identical(digest::digest(".scratch/m2/m2_correspondence.csv", algo = "sha256", file = TRUE), "7874b82ff9f8144c2844dd75a4f611401430a4416542d2c7a00f2e50376d412d"))'
```

The published gzip file and portable manifest are verified independently from a
current checkout with:

```bash
Rscript scripts/m3_validate_release.R --remote
```

The first sequence reproduces the source correspondence bytes; the second
sequence verifies the immutable public artifact and manifest that users
download. Do not treat an unverified recompression as byte reproduction of the
published `.csv.gz` file.

## Correspondence schema

Each row is one `postal_code` and `DBUID` pair. Geography columns available in
the GAF, including `DAUID`, are carried into the output.

- `postal_code`: normalized `ANA NAN` postal code.
- `DBUID`, `DAUID` and available higher geographies: 2021 census identifiers.
- `n_observations`: valid NAR address rows with coordinates.
- `n_unique_addresses`: distinct `LOC_GUID` values in the pair.
- `n_sources`: `1` for this NAR-only build.
- `address_weight`: pair unique-address count divided by the postal code total;
  weights sum to `1` per postal code.
- `best_link`: logical flag for the winner per postal code, selected by highest
  unique-address count and lexical `DBUID` tie-break.
- `confidence`: same value as `address_weight`, documented as an evidence
  concentration score and not a probability.
- `source_vintage`: `2026-06-26`.
- `census_vintage`: `2021`.

The JSON manifest records source URLs and paths, SHA-256 values, code version,
UTC build time, row counts, and validation results.

## Published artifact

The verified 2026-06-26 source-vintage artifact is tracked under
`releases/m2/2026-06-26/`:

- `opcc_m2_correspondence.csv.gz`: 414,207 postal-code/DBUID rows for 282,409
  postal codes.
- `m2_manifest.json`: portable provenance, checksums, code version, build
  timestamp, row counts, and validation results.

The compressed artifact SHA-256 is
`184b7a107049b145c98a3ab37e0fb789c492272aa26e5ab6a41bb5d400bc63e7`.
Its uncompressed CSV SHA-256 is
`7874b82ff9f8144c2844dd75a4f611401430a4416542d2c7a00f2e50376d412d`.

## Tests

The synthetic tests do not require NAR, shapefile, or GAF downloads:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-m2-correspondence.R")'
```

The full build requires `sf`, `dplyr`, `readr`, `jsonlite`, and `digest`.
Spatial observations without a usable coordinate or DBUID are excluded from
the evidence input; missing required files, schema columns, GAF mappings,
duplicate keys, ambiguous multi-DBUID polygon matches, or invalid weight
invariants fail the build.
