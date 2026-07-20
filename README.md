# OPCC

Open Postal Code Conversion is an open, reproducible Ontario postal-code
correspondence pipeline becoming a community-maintained R package.

OPCC is intended for common workflows that otherwise require access to
PCCF/PCCF+: normalize a postal code, resolve it to 2021 Census geography,
retain weighted many-to-many links, select an explicit best link when needed,
and inspect the source, confidence, lineage, and vintage behind every result.
It does not copy or redistribute Canada Post or licensed PCCF/PCCF+ data and
does not claim authoritative postal assignments.

## Current status

| Milestone | Status | Current deliverable |
| --- | --- | --- |
| M1 | Complete | NAR-derived centroids and 17,373 source-labeled GeoNames fallback points |
| M2 baseline | Published | 414,207 NAR postal-code/DBUID rows covering 282,409 postal codes |
| M2 amendment | Review candidate | 431,541 rows / 299,743 postal codes: NAR plus 17,334 GeoNames point-in-polygon links |
| M3 | Review candidate | Installable R package, tests, vignette, release index, and validator |
| M4 | Complete | Source-separated GeoNames coverage enrichment, local source layers, contribution bundles, and source/correction issue templates |

The M2 GeoNames amendment and M3 package are committed in the review branch
`agent/m2-m3-community-package` and await review/merge. The immutable NAR
baseline remains under `releases/m2/2026-06-26/`; it is never overwritten.

The M1 reference layer retains all 17,373 GeoNames-sourced fallback points.
Of these, 17,334 intersect a 2021 Ontario DB/DA and are separately labeled M2
supplementary evidence. The other 39 remain explicitly unmatched rather than
receiving a fabricated link. GeoNames accuracy is source metadata, not a
probability or confidence score, and GeoNames points are never silently treated
as NAR address evidence.

## Verify a release

From a source checkout, verify the versioned M2 baseline and its release index:

```bash
Rscript scripts/m3_validate_release.R
```

The M3 package passes `R CMD check`, including its test suite and rendered
vignette. It exposes `normalize_postal_code()`, `pc_to_geo()`,
`get_correspondence()`, `list_vintages()`, `release_manifest()`,
`validate_release()`, and `pc_to_point()`.

The release index uses commit-pinned GitHub raw URLs so a published artifact
cannot change when `main` advances. The repository must be public for those
checksum-verified remote downloads to be available to unauthenticated clients.
After publication, run the validator with `--remote` to test the endpoint:

```bash
Rscript scripts/m3_validate_release.R --remote
```

The remote command verifies the downloaded manifest and compressed CSV against
their SHA-256 values, then checks unique postal-code/DBUID keys, allocation
weights, and one `best_link` per postal code.

## Rebuild the current candidate

The frozen 2026-06-26 baseline is verified above. Rebuilding from the current
public sources produces the newer NAR-plus-GeoNames candidate, not a
byte-for-byte replacement for that baseline. The full workflow downloads large
git-ignored inputs to `.scratch/`; never commit those inputs or overwrite a
versioned release directory.

```bash
Rscript scripts/m1_nar_profile.R
Rscript scripts/m4_geonames_profile.R
Rscript scripts/m1_build_centroids.R
Rscript scripts/m1_gaf_rollup.R
Rscript scripts/m2_build_correspondence.R
```

Before the GAF rollup, place the public 2021 DB boundary shapefile and
Geographic Attribute File at the paths documented in
[`docs/m1-reproduction.md`](docs/m1-reproduction.md). The detailed, executable
guide is [`docs/reproduce-m2-artifact.qmd`](docs/reproduce-m2-artifact.qmd).

## Product direction

M3-M7 build the public package and its community infrastructure:

- M3: installable R package, lookup API, release cache, and verification tools;
- M4: source-qualified coverage enrichment, local user-data layers, and
  contributor-ready adapters;
- M5: direct weighted postal-code-to-DA roll-up through DB;
- M6: clean-room reproducible and independently verified releases; and
- M7: durable community governance, contribution, correction, and citation.

Every published release must be useful without the bulk build inputs,
rebuildable from public-source manifests and checksums, independently
verifiable, and open to fixture-backed contributions.

## Optional: use your own open data locally

The M4 foundation lets users validate and use their own postal-code evidence as
an explicitly local, source-labeled layer. Every local-data function states
that the layer is separate and invites users with redistributable evidence to
generate a contribution bundle and open an OPCC issue or pull request. Local
data never silently merges into a canonical OPCC release. Do not use Canada
Post, PCCF, PCCF+, or other restricted data.

```r
source("R/opcc.R")
my_postal_data <- utils::read.csv("/path/to/open-data.csv", stringsAsFactors = FALSE)

# The source postal column is named "postal" here. Coordinates, if present,
# must be named latitude and longitude and use decimal degrees.
adapter <- new_source_adapter(
  source_id = "municipal_registry",
  licence = "Open Government Licence",
  lineage = "municipal address registry",
  schema_map = list(postal_code = "postal"),
  checksum = digest::digest("/path/to/open-data.csv", algo = "sha256", file = TRUE)
)
layer <- build_source_layer(my_postal_data, adapter)
profile_source_layer(layer)
contribution_bundle(layer, output_dir = "local-contributions")
```

`geonames_supplementary_adapter()` supplies the checked, versioned metadata for
the current GeoNames supplementary-point artifact. It remains a separate point
layer and never promotes GeoNames coordinates to NAR address evidence.

The reproducible GeoNames coverage/disagreement report is available at
`docs/m4-geonames-coverage-report.md`. There are no shared NAR/GeoNames postal
codes, so cross-source uncertainty weighting is not applicable to this layer.
OPCC retains its deterministic, source-qualified point link and does not
publish invented weights. Calibration becomes a requirement only for a future
layer with independently overlapping evidence.

The source table must contain the field declared as `postal_code` in the
adapter schema map. Optional `latitude` and `longitude` must appear together
and be valid decimal-degree coordinates. Canada Post, PCCF, and PCCF+ data are
rejected; only redistributable evidence can enter a contribution bundle.

See `docs/ROADMAP.md` for milestone contracts and
`docs/m2-reproduction.md` for the current release schema and verification
details. See `docs/reproduce-m2-artifact.qmd` for executable verification,
rebuild, and optional local-data import instructions. See
`docs/m4-contributing-source.md` for the local-layer and
contribution workflow. See `docs/uncertainty-and-allocation-design.md` for the uncertainty
model and reproducible build, calibration, validation, and release pipeline.
