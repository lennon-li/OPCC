# OPCC Roadmap: Open Postal Code Conversion

Status: adopted 2026-07-17. Product name: **OPCC (Open Postal Code
Conversion)** - an open, reproducible Ontario postal-code correspondence
system inspired by the useful functions of PCCF/PCCF+ without copying or
redistributing restricted Canada Post or licensed PCCF data.

Guiding principle: **PCCF+ is a product; OPCC is a pipeline.** StatCan sells
a periodically refreshed file; we publish a reproducible build process whose
releases are keyed to the semi-annual NAR cadence. Anyone can rebuild any
vintage from code plus recorded source checksums.

Non-negotiable constraints (apply to every milestone):

- The evidence unit is an **observed postal association** (postal_code,
  address, lat/lon, source, lineage fields) - never a reconstructed Canada
  Post assignment, never a postal polygon.
- Postal-to-geography links are many-to-many with weights and confidence.
- The Ontario "Canada Postal Code Data" resource and all Canada Post / PCCF
  licensed products stay quarantined: never downloaded, ingested, or
  redistributed.
- Bulk downloaded data is never committed; every ingested file is recorded
  by URL, release date, and checksum so builds are reproducible.
- ODbL sources (OSM) live in a separately designed layer, never the default
  combined product.
- Committed text files are ASCII-only.

## Milestones

### M1 - NAR profiling proof of concept (in progress)

The implementation gate defined in
`docs/ontario-postal-source-survey-plan.md`. Reproducible-from-code
pipeline: download the current NAR release (catalogue 46-26-0002, release
2026-06-26); record URL, checksum, size, schema, release metadata; extract
Ontario; profile postal-code completeness and validity (regex
`^[A-Z][0-9][A-Z][ ]?[0-9][A-Z][0-9]$`, normalize `ANA NAN`); assign
observations to 2021 Dissemination Blocks; derive higher geographies via the
Geographic Attribute File; emit quality and lineage reports. Exit criteria:
manifest `statcan_nar.ingestion_endpoint` filled and `profile_status:
complete`; supporting-geography endpoints documented; all metrics reproduced
by committed scripts.

### M2 - First correspondence table

Status: **COMPLETE** (2026-07-18). The NAR 2026-06-26 correspondence and
portable build manifest are tracked under `releases/m2/2026-06-26/`.

The first artifact that is actually OPCC: `postal_code x DBUID` (rolled up
to DAUID and higher) with n_observations, n_unique_addresses, n_sources,
address_weight, best_link, confidence, source_vintage, census_vintage.
NAR-only at first. Published as a versioned release artifact with a build
manifest (source checksums, code version, build date). Weights driven by
observed address evidence, not population splitting.

### M3 - R package skeleton (OPCC)

Package `OPCC` wrapping the release artifacts: `pc_to_geo()` (postal code in,
geography out, with weight/confidence and vintage selection) and
`get_correspondence()` (fetch/load a full correspondence vintage). Follows
the ONgeoR conventions (ASCII-only, testthat, provenance attributes on
returned objects).

### M4 - Multi-source enrichment

Add sources one at a time, each gated on its own reproduced profiling
metrics per the decision vocabulary in
`research/ontario-postal-source-decisions.md`: ODA (defer-validation:
lineage and regression comparison), GeoNames (accept-supplementary: separate
reference layer), Toronto One Address Repository (conditional-accept: first
municipal), then further municipal discovery. Multi-source agreement raises
confidence only across independent lineages.

### M5 - Health-geography crosswalks

Compose OPCC correspondences with ONgeoR layers (PHU, sub-region, and other
health geographies) so postal codes resolve to health geography with
transparent two-step lineage (postal -> DB -> health unit). OPEN DECISION:
whether these crosswalks ship inside OPCC, inside ONgeoR, or as a thin
compose layer between the two.

### M6 - Sustainable refresh loop

The pipeline that keeps OPCC alive without hand labor: a scheduled update
detector (monthly check of NAR catalogue metadata); full rebuild only when a
new NAR release appears (semi-annual); rebuild runs as a cloud routine that
pushes a release branch and a run-brief issue; a human publish gate (nothing
released without operator sign-off); drift alarms comparing successive
vintages; immutable published vintages (a released correspondence is never
edited, only superseded).

### M7 - Community and governance

Contribution guide, source-proposal template (mirroring the ONgeoR
data-source-request issue form), licence stack documentation per layer
(OGL-Canada, CC BY 4.0, OGL-Toronto, ODbL-separate), and the standing
disclaimer: OPCC is not affiliated with Canada Post or Statistics Canada and
is not PCCF; it publishes observed postal associations from open data.
OPEN DECISION: distribution channel for release artifacts - GitHub Releases
only, or Zenodo with DOIs for citability.

## Open decisions

1. ~~Product/package name~~ - settled 2026-07-17: **OPCC**.
2. Where health crosswalks live (M5): OPCC vs ONgeoR vs compose layer.
3. Release channel (M7): GitHub Releases vs Zenodo/DOI.
