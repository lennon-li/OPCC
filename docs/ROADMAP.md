# OPCC Roadmap: Open Postal Code Correspondence

Status updated: 2026-07-21

OPCC is an open, reproducible Ontario postal-code-to-census-geography package
and data pipeline. The name expands to **Open Postal Code Correspondence** so
the project can retain the same identity if coverage expands beyond Ontario.
Ontario remains the only supported jurisdiction at present.

OPCC is not a drop-in or authoritative replacement for Canada Post, PCCF, or
PCCF+. It publishes source-qualified observed postal associations derived from
redistributable public evidence.

## Non-negotiable constraints

- The evidence unit is an observed postal association, never a reconstructed
  Canada Post assignment or a postal polygon.
- Postal-to-geography relationships may be many-to-many.
- Allocation weights describe observed evidence distribution; they are not
  automatically probabilities or calibrated confidence scores.
- Canada Post, PCCF, PCCF+, and restricted Ontario postal data are never
  downloaded, ingested, or redistributed.
- ODbL sources require a separately designed layer and are not silently merged
  into the default product.
- Published releases are immutable and independently verifiable using manifests
  and checksums.
- Unmatched, NAR-backed, and supplementary-only results remain distinguishable.
- New sources enter through documented adapters, provenance review, licensing
  review, profiling, fixtures, and regression checks.

## Completed milestones

### M1 - NAR profiling and geographic assignment

**Complete.** Profiles the Statistics Canada NAR, extracts Ontario observations,
normalizes postal codes, builds address-derived postal centroids, retains a
separate GeoNames supplementary point layer, assigns points to 2021
Dissemination Blocks, and derives higher geographies through the GAF.

### M2 - Source-qualified DB correspondence

**Published.** Provides immutable, versioned postal-code-to-DB correspondence.
The NAR baseline and GeoNames amendment remain source-separated. All defensible
links, allocation weights, best-link indicators, methods, lineages, and
vintages remain visible.

### M3 - R package foundation

**Complete.** Provides the installable package, lookup API, release cache,
release index, fixtures, vignette, tests, and standalone release validator.
Core functions include `normalize_postal_code()`, `pc_to_geo()`,
`pc_to_point()`, `get_correspondence()`, `get_da_correspondence()`,
`list_vintages()`, `release_manifest()`, and `validate_release()`.

### M4 - Source-qualified enrichment and contributions

**Complete.** Provides source adapters, GeoNames coverage reporting, strict
local-data validation, source-separated local layers, contribution bundles,
and source/correction issue templates. Restricted data cannot enter a bundle.
No cross-source probability is invented where independent overlapping evidence
does not exist.

### M5 - Direct DA correspondence

**Published.** Rolls the versioned DB correspondence to Dissemination Areas
through tracked GAF attributes. DA allocation weights, deterministic best links,
contributing DB identifiers, source vintages, census vintage, and evidence class
remain inspectable.

### M6 - Release assurance

**Complete.** The external Hermes maintenance workflow performs source-vintage
monitoring, isolated producing and verification rebuilds, deterministic drift
reporting, and a mandatory human publication gate. Operational run evidence is
maintained outside package and CRAN scope.

### M7 - Public governance

**Complete.** Governance, conduct, security, release and deprecation policy,
attribution, citation, contribution procedures, and maintainer guidance are
public. GitHub Releases is the durable artifact distribution channel.

## Deferred work

### CRAN readiness

Resolve current `R CMD check --as-cran` notes and complete a full manual- and
vignette-enabled CRAN-level check before any CRAN submission.

### External validation and adoption

Independent external validation is intentionally deferred and tracked in OPCC
project memory. It should test real Ontario workflows, urban and rural cases,
PO-box and unmatched behavior, many-to-many outputs, source-class coverage,
installation usability, and legally permissible benchmark comparisons.

### Additional source coverage

Municipal address-source discovery beyond Toronto, facility anchors,
business/regulated sources, and consolidated geography-endpoint documentation
remain future enrichment work.

## Release artifact policy

Git should retain code, manifests, checksums, schemas, documentation, and small
fixtures. Production data artifacts should be published as immutable,
checksum-pinned GitHub Release assets rather than accumulated indefinitely in
repository history.

## Current scope declaration

- Product: OPCC - Open Postal Code Correspondence
- Supported jurisdiction: Ontario
- Census vintage: 2021
- Primary current source vintage: NAR 2026-06-26
- Durable distribution: GitHub Releases
- DOI mirror: none planned
