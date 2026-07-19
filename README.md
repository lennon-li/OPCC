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

```r
Rscript scripts/m3_validate_release.R
```

The M3 package passes `R CMD check`, including its test suite and rendered
vignette. It exposes `normalize_postal_code()`, `pc_to_geo()`,
`get_correspondence()`, `list_vintages()`, `release_manifest()`,
`validate_release()`, and `pc_to_point()`.

The GitHub repository is currently private to unauthenticated clients. As a
result, checksum-verified remote artifact downloads are an external-publication
gate rather than a currently usable public service. Once an intentional public
release endpoint exists, run the validator with `--remote` to test it.

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

From M4, users will be able to validate and use their own postal-code evidence
as an explicitly local, source-labeled layer. Every such function will invite
users with redistributable evidence to generate a contribution bundle and open
an OPCC issue or pull request. Local data will never be silently merged into a
canonical OPCC release.

See `docs/ROADMAP.md` for milestone contracts and
`docs/m2-reproduction.md` for the current release schema and verification
details. See `docs/uncertainty-and-allocation-design.md` for the uncertainty
model and reproducible build, calibration, validation, and release pipeline.
