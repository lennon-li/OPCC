# OPCC Roadmap: Open Postal Code Conversion

Status: adopted 2026-07-17; M3-M7 community-package audit completed
2026-07-18. Product name: **OPCC (Open Postal Code Conversion)**.

OPCC aims to be the go-to open Ontario package for common workflows that
otherwise require PCCF/PCCF+: normalize postal codes, resolve them to census
geography, retain all plausible links and weights, select an explicit best
link when needed, and inspect vintage, source, confidence, and lineage. It is
not a drop-in or authoritative replacement for Canada Post or licensed PCCF
products; unsupported use cases and unmatched codes must remain visible.

Guiding principle: **OPCC is both a reproducible pipeline and a usable
package.** Published data are immutable, versioned outputs of public inputs
and committed code. Every release must be rebuildable from recorded source
metadata and checksums, independently verifiable, and usable without access
to the bulk build inputs.

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
- APIs never hide coverage gaps: unmatched, NAR-backed, and supplementary-only
  results are distinguishable in returned data.
- A release is not complete until its schema, hashes, row counts, key
  invariants, source licences, and rebuild instructions are machine-checkable.
- New sources enter through a documented adapter and profiling contract, not
  through one-off merges.

## Product acceptance standards

Every remaining milestone must improve at least one of these standards without
weakening the others:

1. **Useful**: common postal-to-census workflows are available through a small,
   documented API with honest many-to-many behavior and explicit fallbacks.
2. **Reproducible**: a clean environment can rebuild each derived artifact
   from versioned code, public input references, checksums, and locked
   dependencies.
3. **Verifiable**: users and CI can validate downloaded artifacts, schemas,
   invariants, vintages, and provenance without trusting the maintainer.
4. **Contributable**: a contributor can propose a source, implement its adapter,
   run fixtures and checks, and submit a reviewable change from documented
   instructions.
5. **Maintainable**: releases, compatibility, corrections, and maintainer
   responsibilities follow a public process that does not depend on one person.

## Milestones

### M1 - NAR profiling proof of concept

Status: **COMPLETE**. The pipeline downloads and profiles the NAR, extracts
Ontario, normalizes postal codes, creates NAR address-derived centroids, retains
a separate GeoNames supplementary point layer, assigns points to 2021
Dissemination Blocks, and derives higher geographies through the GAF. Build
inputs and generated artifacts retain release, licence, method, and lineage
metadata.

### M2 - Source-qualified correspondence table

Status: **VERIFIED REVIEW CANDIDATE** (2026-07-19; scope corrected
2026-07-18). The immutable NAR 2026-06-26 baseline and portable build manifest
remain tracked under `releases/m2/2026-06-26/`. The amended candidate is
committed on `agent/m2-m3-community-package` and is not published until review
and merge.

The first artifact that is actually OPCC: `postal_code x DBUID` with DAUID
and higher identifiers, `n_observations`, `n_unique_addresses`,
`n_sources`, source-qualified weights, `best_link`, source method and quality,
`source_vintage`, and `census_vintage`. NAR rows retain all observed-address
DB links and address weights. Of the 17,373 GeoNames-sourced fallback points,
17,334 intersect a 2021 Ontario DB/DA and are included with their
point-in-polygon assignment, `gn_accuracy`, missing address evidence fields,
and a distinct supplementary evidence class. The other 39 remain explicitly
unmatched points in M1/M3 rather than fabricated M2 links.

The independently rebuilt amendment contains 431,541 rows covering 299,743
postal codes: the 414,207-row NAR baseline plus 17,334 resolved GeoNames rows.
A GeoNames allocation weight of one means that its point join generated one
candidate; it does not mean certainty. The existing baseline is not
overwritten. The full semantics and reproducible build gates are defined in
`docs/uncertainty-and-allocation-design.md`.

**M2 amendment exit gate:** the combined artifact preserves source separation,
includes every GeoNames point that has DBUID and DAUID with `gn_accuracy`,
method, and vintage, explicitly retains and reports unmatched points,
reproduces or explains the target counts, passes key,
weight, nullability, and deterministic-order invariants, and is independently
rebuilt and verified before publication.

### M3 - Usable R package foundation

**Status (2026-07-19): VERIFIED REVIEW CANDIDATE.** The package, source-qualified
point artifact, fixtures, rendered vignette, and standalone release validator
are complete and pass `R CMD check`; publication remains gated on review and
merge of `agent/m2-m3-community-package`.

Build an installable `OPCC` package around the published releases. The first
public contract includes:

- `normalize_postal_code()` for strict `ANA NAN` normalization and validation;
- `pc_to_geo()` for postal-code-to-DB lookup with all links, weights,
  `best_link`, confidence, source class, and vintage;
- `get_correspondence()` for checksum-verified download and local caching of a
  selected release;
- `list_vintages()`, `release_manifest()`, and `validate_release()` so users
  can inspect and verify what they loaded; and
- a source-labeled `pc_to_point()` lookup retaining the 17,373 current
  GeoNames-only M1 records instead of dropping them when NAR has no match.

The package ships a lightweight release index and test fixtures; full artifacts
remain versioned release downloads. Defaults return all defensible links.
Selecting one link must be explicit and must preserve the reason it won.
Returned objects carry provenance attributes and never silently substitute a
GeoNames point for NAR address evidence.

**M3 exit gate:** package installation and `R CMD check` pass in a clean
environment; API, cache, offline, invalid-input, unmatched-code, many-to-many,
and checksum-failure tests pass; a vignette reproduces a postal-to-DB lookup
from a fresh library; and one command validates the bundled release index and
published M2 artifact.

Run `Rscript scripts/m3_validate_release.R` from the repository root to
checksum-verify the release index, manifest, and versioned M2 baseline and to
check its key, weight, and best-link invariants. Add `--remote` after the
repository is publicly reachable to verify its commit-pinned download endpoint.

### M4 - Source-qualified coverage enrichment

**Status (2026-07-19): IN PROGRESS.** The local-layer foundation is implemented
on the M2/M3 review branch: adapter metadata, strict local-data validation,
source-separated layers, profile reports, contribution bundles, and source and
correction issue templates. It is deliberately not a completed M4 claim: a
fully gated non-NAR adapter, reproducible combined artifacts, coverage and
disagreement reports, and calibrated uncertainty validation remain required by
the exit gate below. The current GeoNames/NAR report is reproducible and
honestly records calibration as not estimable because the source layers have
zero shared postal codes; it does not manufacture uncertainty weights. CI runs
the versioned coverage report and package checks, including restricted-source,
provenance, fixture, duplicate-evidence, and source-separation tests.

Add public sources one at a time through a reusable source-adapter contract.
Each adapter declares its licence, lineage, retrieval endpoint, release date,
checksum, schema mapping, normalization rules, quality metrics, and fixtures.
The initial order remains ODA for lineage/regression comparison, GeoNames as a
separate supplementary point layer, Toronto as the first municipal source, and
then verified municipal or facility sources.

#### User-supplied data and contribution path

M4 provides an explicit local-layer API for organizations and researchers that
hold postal-code evidence OPCC does not yet publish. The planned functions are
`validate_source_data()`, `new_source_adapter()`, `build_source_layer()`,
`profile_source_layer()`, and `contribution_bundle()`. They validate a user
table, normalize it into a source-labeled layer, report coverage/conflicts and
uncertainty, and create a reviewable contribution bundle. A local layer can be
passed explicitly to lookup/build functions, but is never silently merged into
a canonical OPCC release or used to overwrite NAR evidence.

**Contribution invitation:** every public function that accepts, creates, or
profiles user-supplied postal-code data must emit a concise `message()` on
every invocation: the layer remains local and source-separated; if its licence
permits redistribution, the user is invited to submit the generated bundle as
an OPCC issue or pull request. `contribution_bundle()` must produce a
normalized sample/fixture, provenance and licence declaration, retrieval or
creation date, schema map, quality/coverage report, and reproducible adapter
configuration. It must never package restricted Canada Post/PCCF/PCCF+ data.

The repository will provide issue and pull-request templates for new sources
and corrections. CI applies the same licence, provenance, fixture, duplicate,
and regression checks to contributed layers as to maintainer-built layers;
acceptance remains a maintainer review decision with the evidence layer kept
inspectable.

The 17,373 current GeoNames-sourced fallback codes remain available. Better
open address or facility evidence may supersede their coordinates for a
specific layer, but unresolved codes are retained with
`source_class = supplementary` and explicit precision limitations. Agreement
raises confidence only across independent lineages; source layers remain
inspectable and are never blended into an opaque score.

M4 also implements the calibrated uncertainty layer defined in
`docs/uncertainty-and-allocation-design.md`: empirically calibrated candidate
DB/DA sets based on held-out NAR/GeoNames overlap, spatially blocked validation,
and source/density/rurality strata. All candidate weights remain visible;
seeded random allocation is optional and never the default lookup behavior.

**M4 exit gate:** at least one non-NAR adapter completes the full profiling and
licence gate; source-specific and combined artifacts are reproducible; coverage
and disagreement reports quantify additions, supersessions, and unresolved
codes; held-out uncertainty metrics and calibration by stratum beat or honestly
fail against point-only, equal-weight, and population-only baselines; and CI
rejects missing provenance, incompatible licences, duplicate evidence, or
unexplained coverage loss. The local-layer API, per-invocation contribution
invitation, contribution-bundle schema, and issue/PR templates are tested;
fixtures demonstrate that local data remains source-separated and that
restricted data cannot enter a bundle.

### M5 - Postal-code to DA roll-up

Publish a direct postal-code-to-Dissemination-Area artifact and extend
`pc_to_geo(level = "DA")` by rolling postal-code-to-DB evidence through the 2021 GAF DB-to-DA relationship.
Aggregate weights across contributing DBs, preserve many-to-many DA links,
recompute deterministic `best_link`, and retain contributing-DB counts and
lineage. This is an attribute roll-up, not a new point or polygon assignment.

**M5 exit gate:** DA weights sum to one per covered postal code; each covered
postal code has exactly one deterministic best DA; every DA result traces to
its contributing DB rows and release vintages; no identifier is missing; the
artifact and manifest pass `validate_release()`; and package examples cover
single-link, multi-link, supplementary-only, and unmatched postal codes.

### M6 - Reproducible and independently verifiable releases

Create the release system that keeps OPCC current without hand-built data. It
includes a monthly NAR metadata check, rebuilds only for new source vintages,
locked R dependencies, recorded build environment, deterministic artifacts,
schema and invariant checks, successive-vintage drift reports, and a clean-room
rebuild job independent of the producing job.

Automation opens a release branch and run-brief issue containing source diffs,
checksums, coverage changes, validation results, and reviewer actions. A human
publish gate remains mandatory. Published vintages are immutable and can only
be superseded.

**M6 exit gate:** a clean runner rebuilds the candidate from manifests and
public inputs; a separate verification job confirms artifact hashes and
semantic invariants; deliberate source/schema/hash drift fails loudly; rollback
and correction procedures are documented; and the complete release can be
reproduced without maintainer-local files.

### M7 - Community-maintained public project

Publish the governance needed for OPCC to outlive its initial maintainers:
`CONTRIBUTING.md`, code of conduct, source-proposal and data-correction issue
templates, adapter scaffolding, reviewer checklist, maintainer roles, decision
record process, release and deprecation policy, security/contact policy, and a
licence/attribution matrix for every layer.

Community review requires two separable approvals for data changes: technical
validation and provenance/licence review. Contributor fixtures must be small
and redistributable. CI provides the same checks maintainers use. Governance
defines how maintainers are added or removed, how disputed source claims are
resolved, and how abandoned releases remain reproducible.

The standing disclaimer remains: OPCC is not affiliated with Canada Post or
Statistics Canada, is not PCCF/PCCF+, and publishes source-qualified observed
postal associations from open data. Documentation also states which common
PCCF/PCCF+ workflows OPCC supports and which it does not.

**M7 exit gate:** a new contributor can add a fixture-backed source adapter by
following only public documentation; a new maintainer can execute and verify a
release without private instructions; governance and correction drills are
completed; and release artifacts have durable distribution and citation.

## Open decisions

1. ~~Product/package name~~ - settled 2026-07-17: **OPCC**.
2. ~~M5 design~~ - settled 2026-07-18: direct postal-code-to-DA roll-up
   through DB.
3. M7 durable distribution: GitHub Releases only, or GitHub Releases plus
   Zenodo/DOI for citation and archival redundancy.
