# M2 Reproduction Guide

M2 builds a NAR-only correspondence from observed address evidence. It does not
reconstruct Canada Post assignments and does not use restricted Ontario postal
data or licensed PCCF data.

## Inputs

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
