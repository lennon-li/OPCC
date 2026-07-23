# M5 Direct DA Correspondence

M5 is a deterministic attribute roll-up from versioned M2 postal-code-to-DB
evidence to 2021 Dissemination Areas (DAs). It does not perform a spatial join,
construct postal polygons, or change the source evidence.

## Input mapping

The versioned M2 artifact already contains the `DBUID` and `DAUID` pair from
the pinned 2021 Statistics Canada Geographic Attribute File. Thus the current
M5 build needs no new raw input or boundary download: it reads the tracked M2
artifact and groups its DB links by `postal_code` and `DAUID`.

## Build

Run this from the repository root:

```bash
Rscript scripts/m5_build_da_correspondence.R
```

The command writes `releases/m5/2026-06-26/` with:

- `opcc_m5_da_correspondence.csv.gz`, one `postal_code` x `DAUID` row;
- `m5_manifest.json`, with M2 input checksums, method, counts, and artifact
  checksums.

For each postal code, M5 sums M2 allocation weights for DBs belonging to the
same DA. It retains `n_contributing_dbs`, a stable pipe-delimited
`contributing_dbuids` trace, source and census vintages, and source evidence
classes. The DA with the highest aggregate weight is `best_link`; exact ties
use lexical `DAUID` order.

## Verify and use

After the artifact is listed in `inst/extdata/release-index.json`, verify it
through the package:

```r
validate_release(level = "DA")
pc_to_geo("K1A 0A6", level = "DA")
```

DA weights must sum to one per covered postal code, every postal code must have
exactly one `best_link`, and every row must retain DB and release-vintage
lineage.

## External-reference comparison

M5 release `2026-07-20` was compared by the maintainer with a licensed,
PCCF-derived March 2023 Ontario DA export. The aggregate-only result reports
99.46% any-link agreement across 280,649 shared postal codes, 95.65% OPCC
best-link containment, 91.83% exact-set agreement, and 88.97% pair precision.
The reference supplies one DA per code while OPCC retains additional candidate
links, and the source vintages differ.

See `docs/validation-summary.md` and
`docs/validation/pccf-da-2023-public-attestation.json` for the complete scope,
provenance, and limitations. This comparison does not validate M1 coordinates
or M2 DB correspondence.
