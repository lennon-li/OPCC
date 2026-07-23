# OPCC Validation Reproduction Guide

This document explains how to reproduce the validation outputs in `docs/validation_report.md` and the three PNGs (`validation_ecdf.png`, `validation_hist.png`, `validation_box.png`).

## What is being validated

The validation compares the public OPCC Ontario postal centroid release against a reference coordinate set. The current public centroid release is:

```text
releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz
releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json
```

It contains one row per distinct Ontario postal code with a lat/lon point, a `point_source` column (`nar_centroid`, `geonames`, or `none`), and full provenance. The release is redistributable under the NAR Open Government Licence - Canada and the GeoNames CC BY 4.0 licence.

## Restricted-input boundary

A rigorous comparison against the official Statistics Canada PCCF/SLI extracts requires access to those restricted licensed products. OPCC does not redistribute them.

- PCCF/SLI extracts are **maintainer-held, local, read-only QA material** under an explicit maintainer exception.
- They are **not** a package input, release artifact, contribution input, fixture, or redistributed OPCC content.
- The validation pipeline accepts a local SLI/PCCF CSV path, but it never copies, caches, serialises, or commits row-level SLI/PCCF data.
- Licensed validation output must be written outside the repository. The
  current licensed report and plots are private review material, not approved
  public artifacts. The M5 DA benchmark has a separate, disclosure-minimised
  public aggregate attestation under `docs/validation/`.
- Public users can reproduce the pipeline, but an empirical PCCF/SLI comparison requires their own authorised access to the required restricted input.
- The repository does not assert any licence, access right, or legal conclusion for PCCF/SLI beyond the maintainer exception described here.

## Required tools

- R (>= 4.1)
- R packages: `readr`, `dplyr`, `ggplot2`, `jsonlite`, `digest`, `scales`

## Reproduce with the public synthetic benchmark

When no local SLI/PCCF input is available, the generator produces a deterministic synthetic benchmark from the public centroid table. This exercises the pipeline but does not assert empirical accuracy.

The `--producer-ref` argument is required. It records the commit that contains the generator scripts and validates that the revision exists and contains every named script. The committed outputs were produced with the producer revision recorded in `docs/validation_manifest.json` under `generator.repo_sha`.

The `--producer-ref` argument accepts any valid git ref (abbreviated SHA, branch name, tag, etc.) and resolves it to the full 40-character commit SHA before writing to the manifest.

```bash
Rscript scripts/sli_validate.R \
  --centroid-csv releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz \
  --centroid-manifest releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json \
  --producer-ref 707bd743c8f0805010bee5cd60c5055a3081c206 \
  --synthetic \
  --output-dir docs
```

## Reproduce with a local SLI/PCCF QA extract

If you have authorised local access to a SLI/PCCF extract, prepare a CSV with at least these columns:

- `postal_code` (also accepted: `postalcode`, `pc`, `mail_postal_code`, `postal_cd`)
- `latitude` (also accepted: `lat`)
- `longitude` (also accepted: `lon`, `long`)

Then run:

```bash
Rscript scripts/sli_validate.R \
  --centroid-csv releases/m1/2026-06-26-nar-geonames-centroids/opcc_m1_centroids.csv.gz \
  --centroid-manifest releases/m1/2026-06-26-nar-geonames-centroids/m1_manifest.json \
  --producer-ref 707bd743c8f0805010bee5cd60c5055a3081c206 \
  --sli-csv /path/to/local/sli_qa.csv \
  --sli-label "PCCF SLI QA" \
  --output-dir /path/outside/opcc/private-validation
```

The pipeline will normalise postal codes, preserve distinct reference
coordinates, compare each OPCC point with its nearest same-code reference
coordinate, stratify Haversine distances by `point_source`, and emit a private
report, plots, metrics JSON, and validation manifest. Do not copy these outputs
into the repository. A separate allowlisted publisher is required before
licensed aggregate results can become public. The parent of a new licensed
output directory must already exist so its canonical location, including any
symbolic links, can be checked before writing.

## Many-to-many correspondence metric engine

`R/validation-metrics.R` also provides pure internal helpers for
licensed DB/DA benchmark work:

- `sli_normalize_link_table()` preserves distinct postal-code/geography pairs,
  collapses only exact duplicate reference pairs, and validates Ontario DB or
  DA identifiers.
- `sli_compute_link_metrics()` compares OPCC and reference geography sets for
  shared codes and returns aggregate-only coverage, precision, recall, F1,
  missing/excess links, micro/macro Jaccard, any-link agreement, exact-set
  agreement, and OPCC-best-link containment.

The engine is exercised with synthetic PCCF-shaped fixtures. It does not read,
publish, or ship licensed data, and it is not yet a public package API.

## Private M1/M2/M5 PCCF runner

`scripts/pccf_validate.R` runs the complete private benchmark against an
authorised Ontario PCCF extract. It verifies M1, checks M2 and M5 against
`inst/extdata/release-index.json`, and requires M5 to name the exact selected
M2 artifact and manifest hashes. Matching 2021 census vintages and M1/M2 NAR
vintages are also required before the licensed input is read.

The PCCF CSV must remain outside the repository. Copy
`config/pccf-validation-contract.example.json` to a private location, replace
`product_vintage`, and adjust only the five source column names. The contract
fixes the benchmark to Ontario, 2021 census geographies, EPSG:4326 coordinates,
strict missing-value handling, and exact-duplicate deduplication.

Both existing M5 releases descend from M2 `2026-06-26`; they are intentionally
incompatible with M2 `2026-07-19-geonames-amendment` for this benchmark.

After this runner is committed, use that commit as `--producer-ref`:

```bash
Rscript --vanilla scripts/pccf_validate.R \
  --m1-release-dir releases/m1/2026-06-26-nar-geonames-centroids \
  --m2-release-id 2026-06-26 \
  --m5-release-id 2026-07-20 \
  --pccf-csv /path/outside/opcc/ontario-pccf.csv \
  --pccf-contract /path/outside/opcc/pccf-contract.json \
  --output-dir /path/outside/opcc/private-pccf-validation \
  --producer-ref <full-commit-sha>
```

The output directory must not already exist and its parent must exist. The
runner creates it with owner-only permissions and writes aggregate metrics, an
aggregate report, and a hash manifest. Outputs contain no postal codes,
coordinates, DBUIDs, DAUIDs, examples, joined rows, or local paths. They remain
private diagnostic evidence; any public attestation requires a separate,
reviewed aggregate allowlist.

### DA-only PCCF-derived XLSX exports

Some licensed exports contain postal codes and DAUIDs but no coordinates or
DBUIDs. `scripts/pccf_da_validate.R` handles that narrower evidence without
claiming M1 or M2 validation. It preserves many-to-many postal-code-to-DA
relationships, verifies the selected M5 release and its M2 parent against the
canonical release index, and records M1 and M2 as unvalidated.
Invalid or unassigned DA sentinels are excluded under the explicit contract
policy and reported only as an aggregate count.

Use `config/pccf-da-validation-contract.example.json` for the March 2023
Ontario export schema:

```bash
Rscript --vanilla scripts/pccf_da_validate.R \
  --m5-release-id 2026-07-20 \
  --pccf-xlsx /path/outside/opcc/PCCF_ON_Mar2023_ExportTable.xlsx \
  --pccf-contract config/pccf-da-validation-contract.example.json \
  --output-dir /path/outside/opcc/private-pccf-da-validation \
  --producer-ref <full-commit-sha>
```

The output remains private. Because the reference is March 2023 while OPCC
uses 2026 source evidence, disagreements may reflect real assignment changes
between vintages as well as OPCC error.

The reviewed public subset from the completed M5 comparison is
`docs/validation/pccf-da-2023-public-attestation.json`. It intentionally omits
the licensed workbook hash, private-output hashes, paths, and row-level values.
See `docs/validation-summary.md` for interpretation.

## Output files

| File | Purpose |
| --- | --- |
| `docs/validation_report.md` | Human-readable report |
| `docs/validation_ecdf.png` | Cumulative accuracy plot |
| `docs/validation_hist.png` | Deviation histogram under 5 km |
| `docs/validation_box.png` | Distance variance by source |
| `docs/validation_metrics.json` | Machine-readable aggregate metrics |
| `docs/validation_manifest.json` | Generator, input, and output hashes |

## Determinism note

The script sets a fixed seed and fixed PNG dimensions. The numeric outputs and metrics are deterministic for a given input set. PNG pixels may differ slightly across graphics backends or R versions, so reproducibility is asserted at the data and metrics level, not at the bit level of the PNG files.

## Rebuild the centroid artifact from scratch

The full public centroid artifact is generated by:

```bash
# 1. Download public source files (not committed):
#    NAR 46-26-0002 2026-06-26 ZIP -> .scratch/m1_nar/202606.zip
#    GeoNames CA_full.csv.zip      -> .scratch/m1_geonames/CA_full.csv.zip
# 2. Run the centroid builder:
Rscript scripts/m1_build_centroids.R
# 3. Publish the release artifact with an explicit producer revision:
Rscript scripts/m1_release.R --producer-ref 707bd743c8f0805010bee5cd60c5055a3081c206
```

See `scripts/m1_build_centroids.R` and `scripts/m1_release.R` for source vintage, licence, attribution, and manifest details.
