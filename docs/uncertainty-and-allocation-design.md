# OPCC Uncertainty and Allocation Design

Status: design baseline, 2026-07-18.

## Purpose

This document defines how OPCC represents uncertainty when linking Ontario
postal codes to 2021 Census geography. It also defines the reproducible
pipeline needed to build, calibrate, validate, and release those links.

OPCC supports common PCCF/PCCF+-style workflows without copying licensed
PCCF/PCCF+ data. It publishes source-qualified evidence and model outputs, not
authoritative Canada Post assignments.

## Core distinction

A Dissemination Block (DB) is a geographic unit, not a population count. Each
2021 DB belongs to exactly one 2021 Dissemination Area (DA). Therefore:

- DB-to-DA roll-up is deterministic;
- postal-code-to-DB assignment can be uncertain; and
- DA uncertainty exists only when plausible DB links roll into multiple DAs.

OPCC keeps three quantities separate:

1. **Evidence weight** describes the observed source evidence among candidate
   links. M2 NAR `address_weight` is the share of unique observed addresses for
   a postal code found in each DB.
2. **Allocation weight** is normalized mass used to distribute records among
   candidate geographies. It is not automatically a calibrated probability.
3. **Confidence** is reserved for externally validated performance. It must be
   missing when no calibration supports a probability-like interpretation.

The number `1` in an allocation field can mean that only one candidate was
generated. It does not, by itself, mean that the assignment is certain.

## Sources of uncertainty

Postal codes are mail-delivery identifiers rather than census polygons. Error
or ambiguity can arise because:

- one postal code serves addresses in several DBs or DAs;
- rural routes, general delivery, post-office boxes, and large-volume
  receivers may identify delivery rather than residence;
- a representative point may be a place point, estimated point, or centroid;
- source coverage and positional quality vary by geography;
- postal codes and census boundaries have different vintages; and
- invalid, retired, partial, or reused postal codes may not represent a current
  residential location.

PCCF+ uses candidate links, population weighting, and random allocation to make
large record sets approximate the population distribution. Such allocation is
not proof of an individual's DA and can be unsuitable for small or specialized
cohorts. OPCC will retain the full candidate distribution by default.

References:

- Statistics Canada, "Accuracy of matching residential postal codes to census
  geography": https://www150.statcan.gc.ca/n1/pub/82-003-x/2020003/article/00001-eng.htm
- GeoNames postal-code readme:
  https://download.geonames.org/export/zip/readme.txt

## M2 corrected correspondence contract

M2 is the source-qualified postal-code-to-DB evidence table. Its amended
release combines, without blending, two evidence classes:

### NAR address evidence

- Grain: one `postal_code x DBUID` row.
- Candidate links: DBs containing observed NAR address coordinates.
- `address_weight`: unique-address share among the postal code's DB links.
- `allocation_weight`: equal to `address_weight`.
- `confidence`: retains the current evidence share for compatibility, but
  documentation must not call it externally calibrated confidence.
- `evidence_class = "nar_address"`.
- `assignment_method = "nar_address_to_db"`.

### GeoNames supplementary point evidence

- Grain: one `postal_code x DBUID` row for the DB containing the GeoNames
  point.
- `allocation_weight = 1` because the deterministic point join generates one
  candidate.
- `address_weight`, `confidence`, `n_observations`, and
  `n_unique_addresses` are missing.
- `gn_accuracy` is preserved as source metadata.
- `evidence_class = "geonames_supplementary"`.
- `assignment_method = "geonames_point_in_polygon"`.

GeoNames documents `accuracy` as a categorical indication of coordinate
method, including `1 = estimated`, `4 = geonameid`, and `6 = centroid of
addresses or shape`. It is not a probability or a distance radius.

The tracked inputs imply the amended M2 target of 431,580 rows covering
299,782 postal codes: 414,207 NAR rows plus 17,373 GeoNames point rows. Of the
GeoNames point rows, 17,025 postal codes are absent from NAR and 348 are present
in NAR but lack a usable NAR-derived point. All 17,373 currently have DB and DA
identifiers in the M1 roll-up.

## Reproducible build pipeline

### Stage 0 - Pin the build specification

The release specification records:

- OPCC code commit;
- source URLs, catalogue identifiers, release/retrieval dates, licences, and
  SHA-256 checksums;
- census vintage and exact boundary/GAF products;
- R version, system libraries, and locked R dependencies;
- coordinate reference systems and transformation library versions;
- random seed, if any stochastic validation or allocation is requested; and
- expected schemas, key invariants, and output ordering.

Inputs are immutable within one build. A source checksum change creates a new
candidate release; it never silently changes an existing release.

### Stage 1 - Acquire and validate sources

Each source adapter performs download, checksum verification, licence checks,
schema validation, and a fixture-backed profile before transformation. Raw
bulk inputs remain outside git. Manifests record enough information for an
independent runner to retrieve the same bytes.

Failures in source retrieval, checksum, schema, licence, or expected Ontario
coverage stop the build. They do not produce a partial release.

### Stage 2 - Normalize source evidence

The NAR adapter joins address and location records, normalizes postal codes,
retains stable source identifiers, and selects coordinates under documented
precedence rules.

The GeoNames adapter normalizes postal codes and retains latitude, longitude,
place name, `accuracy`, retrieval date, licence, and attribution. Duplicate
postal-code rows must be profiled and resolved under an explicit deterministic
rule rather than an undocumented first-row choice.

Invalid and excluded records are written to machine-readable diagnostics with
reason codes and counts.

### Stage 3 - Assign points to 2021 DBs

All source points are transformed from their declared source CRS to the pinned
DB boundary CRS, then spatially joined to Ontario DB polygons.

The build stops on:

- a valid source point outside every Ontario DB;
- a point intersecting multiple DBs without an explicit boundary-resolution
  rule;
- a DB missing from the pinned GAF; or
- a DB whose GAF row lacks DAUID.

Spatial library versions and CRS definitions are recorded because boundary
behavior and coordinate transforms can affect edge cases.

### Stage 4 - Build source-specific DB evidence

NAR address observations are aggregated to unique `postal_code x DBUID` rows.
Unique-address counts produce `address_weight`; deterministic tie-breaking
selects one `best_link` while retaining every link.

GeoNames point assignments remain a separate supplementary table. They are
not combined with NAR counts and are used only where no usable NAR DB evidence
exists for that postal code.

The union is M2. Required invariants include:

- unique `postal_code x DBUID` keys;
- one `best_link` per covered postal code;
- allocation weights summing to one per postal code;
- source-specific nullability rules;
- no missing postal code, DBUID, DAUID, source class, method, or vintage; and
- deterministic row and column order.

### Stage 5 - Roll DB evidence to DA

M5 maps each DBUID through the pinned GAF and sums allocation weights for DBs
belonging to the same DA. It then recomputes deterministic DA `best_link` and
retains contributing DB counts and identifiers.

This stage performs no spatial intersection and adds no uncertainty. It only
propagates and, where possible, collapses existing DB uncertainty.

### Stage 6 - Calibrate uncertainty when paired evidence exists

The deterministic GeoNames point assignment remains available without a
cross-source weighting model. When a source layer has no independently paired
evidence, OPCC does not create or require a calibrated candidate distribution;
the source-qualified point link remains the complete result for that layer. A
separate calibrated layer may be generated only when paired evidence exists.

The calibration population is postal codes independently represented by both
GeoNames and NAR. NAR address distributions are a validation proxy, not perfect
ground truth. Calibration is stratified by at least:

- GeoNames `accuracy` category;
- rural versus urban context;
- local population/dwelling density; and
- source and census vintage.

Training, tuning, and test postal codes are disjoint. The final test set also
uses spatial grouping so nearby postal codes do not leak local geography into
both training and evaluation.

For each stratum, the pipeline estimates empirical distance and DA-mismatch
distributions. Candidate DBs can then be generated from a documented support
region around the point. Candidate weights may combine:

- open address or dwelling evidence, when available;
- DB residential population or dwelling counts;
- distance from the GeoNames point; and
- the fraction of DB area intersecting the support region.

Area fraction must not be used alone because large rural DBs may contain large
uninhabited areas. Every model formula, smoothing choice, zero-population rule,
and fallback is versioned.

The calibrated output retains all candidates. Suggested fields include
`candidate_dbuid`, `candidate_dauid`, `allocation_weight`, `n_candidate_db`,
`n_candidate_da`, `top_weight`, `weight_entropy`, `support_radius_km`,
`support_quantile`, `model_version`, and `calibration_vintage`.

### Stage 7 - Validate a calibrated model

The held-out report compares the calibrated model with at least these
baselines:

- GeoNames point-in-polygon only;
- equal weight among candidate DAs; and
- population-only weighting.

Report overall and stratum-specific metrics:

- point-selected DB and DA agreement with NAR evidence;
- coverage of 50%, 90%, and 95% candidate sets;
- calibration of top weights;
- distribution error against NAR address weights;
- median and upper-quantile point-to-address distance;
- unmatched and zero-population rates; and
- change from the previous source/model vintage.

A nominal 90% candidate set must be assessed against approximately 90%
held-out coverage. If calibration fails for a stratum, or if no independent
paired evidence exists to calibrate it, OPCC publishes the deterministic
supplementary point and a limitation flag rather than a false probability
distribution.

### Stage 8 - Produce and verify a release

Release generation is deterministic: stable sort order, explicit column order,
documented numeric precision, normalized missing values and line endings, and
fixed compression settings. The release manifest contains source and artifact
hashes, row counts, coverage counts, schemas, invariant results, code commit,
environment details, and model-validation references.

A producing job and a separate clean-room verification job independently
build and validate the candidate. Publication requires matching hashes or a
documented explanation of any platform-dependent byte difference plus matching
semantic hashes. Published artifacts are immutable and corrections create a
superseding release.

## User-facing behavior

- Lookups return all defensible links by default.
- Source evidence and model allocation remain inspectable.
- Selecting one best link is explicit and deterministic.
- Random allocation is optional, seeded, and intended only for aggregate
  cohort workflows.
- Supplementary, unmatched, historical, and non-residential-risk results are
  never silently promoted to authoritative residential assignments.
- Users needing individual-level neighbourhood truth are warned that a postal
  code, especially a rural or supplementary-only code, may be insufficient.

## Release gates

The corrected M2 release is ready only when:

- all 17,373 GeoNames point rows are included with required provenance and
  `gn_accuracy`;
- target counts are reproduced from pinned inputs or count changes are
  explained by a new source checksum;
- all source-separation, key, weight, nullability, and geography invariants
  pass;
- the artifact and manifest are rebuilt from a clean environment; and
- an independent verification run confirms hashes and semantic invariants.

The calibrated uncertainty layer is ready only when its held-out and spatially
blocked validation report passes documented thresholds and every published
weight can be traced to a versioned model, input manifest, and calibration
cohort.
