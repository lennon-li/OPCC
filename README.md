# OPCC

[![R package check](https://github.com/lennon-li/OPCC/actions/workflows/r-package-check.yml/badge.svg)](https://github.com/lennon-li/OPCC/actions/workflows/r-package-check.yml)

**Open Postal Code Correspondence** is an open, reproducible R package and data
pipeline for linking Ontario postal codes to Statistics Canada census
geographies.

Current scope: **Ontario**  
Current census vintage: **2021**  
Current primary source vintage: **Statistics Canada NAR 2026-06-26**

OPCC supports common workflows that otherwise require access to PCCF/PCCF+:
postal-code normalization, source-qualified lookup to Dissemination Blocks and
Dissemination Areas, weighted many-to-many correspondence, explicit best-link
selection, and inspection of source, lineage, method, and vintage.

OPCC does not copy or redistribute Canada Post, PCCF, PCCF+, or other restricted
data. It does not claim authoritative postal assignments. Its evidence unit is
an observed postal association derived from redistributable public sources.

## Install

Requires R >= 4.1.

```r
install.packages("remotes")
remotes::install_github("lennon-li/OPCC")
```

## Use pre-built artifacts (most users)

The package downloads, checksum-verifies, and caches published artifacts
automatically on first use. No source checkout or raw data is needed. The
first lookup call downloads the artifact (~15 MB); subsequent calls use the
local cache.

```r
library(OPCC)

# Look up a postal code -> best DA link
pc_to_geo("M5V 3A8", level = "DA", all_links = FALSE)

# Look up a postal code -> every DB link with allocation weights
pc_to_geo("M5V 3A8", level = "DB")

# Download the full artifact as a data frame for joining with your own data
da <- get_da_correspondence(vintage = "2026-07-20")
db <- get_correspondence(vintage = "2026-07-19-geonames-amendment")

# Join to your data
my_data <- data.frame(postal_code = c("M5V 3A8", "K1A 0A6"),
                      stringsAsFactors = FALSE)
merge(my_data, da[da$best_link, c("postal_code", "DAUID", "allocation_weight")],
      by = "postal_code", all.x = TRUE)

# Source-qualified point observations
pc_to_point("K1A 0A6")

# Verify artifact checksums and invariants
validate_release(vintage = "2026-07-20", level = "DA")

# List available release vintages
list_vintages(level = "DB")
list_vintages(level = "DA")
```

See the package vignette for the full user guide, including `dplyr` joins,
offline use, and importing your own open evidence:

```r
vignette("using-opcc", package = "OPCC")
```

## Reproduce and verify artifacts

All published artifacts can be verified and reproduced using package functions
alone -- no source checkout needed:

```r
# Verify checksums and invariants
validate_release(vintage = "2026-07-19-geonames-amendment", level = "DB")
validate_release(vintage = "2026-07-20", level = "DA")

# Reproduce the DA artifact from the DB artifact
db <- get_correspondence(vintage = "2026-07-19-geonames-amendment")
da <- aggregate_da_correspondence(db)
```

Rebuild every artifact from raw Statistics Canada sources, also using
package functions only (requires `sf`, `dplyr`, `readr`):

```r
# Step 1: Download all public inputs (cached, ~1.6 GB)
nar_dir <- download_nar()
geonames_txt <- download_geonames()
bounds <- download_census_boundaries()
gaf_csv <- download_gaf()

# Step 2: Build centroids (M1)
centroids_csv <- build_centroids(nar_dir, geonames_txt)

# Step 3: Assign to DBs and join GAF (M1)
rollup_csv <- build_db_assignment(centroids_csv, bounds$province, bounds$db, gaf_csv)

# Step 4: Build DB correspondence (M2)
m2_csv <- build_m2(nar_dir, bounds$db, gaf_csv, rollup_csv)

# Step 5: Reproduce DA roll-up (M5)
db <- utils::read.csv(m2_csv, stringsAsFactors = FALSE)
da <- aggregate_da_correspondence(db)
```

See Part 2 of the vignette for full detail on each step.

## Current status

| Milestone | Status | Deliverable |
| --- | --- | --- |
| M1 | Complete | NAR profiling, source-qualified points, DB assignment, and GAF roll-up |
| M2 | Published | NAR baseline and source-separated GeoNames amendment |
| M3 | Complete | Installable R package, tests, vignette, release index, and validator |
| M4 | Complete | Source adapters, local layers, contribution bundles, and coverage reporting |
| M5 | Published | Direct weighted postal-code-to-DA correspondence with DB lineage |
| M6 | Complete | External release-assurance workflow with human publication gate |
| M7 | Complete | Governance, security, release, attribution, citation, and contribution policy |

CRAN submission work and independent third-party validation are intentionally
tracked separately from the completed product milestones.

## Validation evidence

OPCC M5 was benchmarked by the maintainer against an authorised, PCCF-derived
Ontario DA export using the aggregate-only validation runner. This is an
external-reference comparison, not an independent audit, certification, or
claim that OPCC is authoritative.

| Measure | Result |
| --- | ---: |
| Comparable postal codes | 280,649 |
| Reference codes covered by OPCC | 95.98% |
| OPCC codes covered by the reference | 99.38% |
| Any-link agreement / pair recall | 99.46% |
| OPCC best-link contained in reference | 95.65% |
| Exact-set agreement | 91.83% |
| Pair precision | 88.97% |
| Pair F1 | 93.92% |

The reference assigns one DA per postal code, while OPCC deliberately preserves
additional defensible many-to-many links. Pair precision and exact-set
agreement therefore penalize the package's additional candidate links. The benchmark
compared a March 2023 reference with M5 release `2026-07-20`, built from June
2026 source evidence; disagreements can reflect real assignment changes
between vintages as well as OPCC error.

This evidence validates M5 DA correspondence only. The reference contains
neither coordinates nor DBUIDs, so M1 coordinate accuracy and M2 DB
correspondence remain without an empirical PCCF comparison. No licensed rows,
workbook hash, private-output hash, or local path is published.

See the [validation summary](docs/validation-summary.md), [public aggregate
attestation](docs/validation/pccf-da-2023-public-attestation.json),
[reproduction guide](docs/validation_reproduction.md), [DA validation
runner](scripts/pccf_da_validate.R), and [checksum-bound M5
manifest](releases/m5/2026-07-20/m5_manifest.json).

Additional safeguards verify release hashes, M5-to-M2 ancestry, schemas,
allocation-weight sums, deterministic best links, Ontario bounds and exact
boundary membership, and 2021 DB assignment. Synthetic PCCF-shaped fixtures
exercise the validation and privacy pipeline without redistributing licensed
data.

## Evidence and uncertainty

OPCC distinguishes three concepts:

- `allocation_weight`: the observed evidence distribution across candidate
  geographies;
- `source_quality`: descriptive metadata about the evidence source and method;
- calibrated confidence: used only when independent overlapping evidence and
  validation support a probabilistic interpretation.

GeoNames accuracy is source metadata, not a probability. GeoNames points remain
separate supplementary evidence and are never silently promoted to NAR address
evidence. Unmatched points remain unmatched.

## Releases and repository size

Production artifacts are intended for immutable GitHub Releases. Git should
retain code, manifests, checksums, schemas, documentation, and small test
fixtures. New full data vintages should not be accumulated in repository
history when a checksum-pinned release asset can provide the same public
contract.

## Community and governance

Contribute only open, redistributable evidence. Local user data remains
source-separated and is never silently merged into a canonical release.
Restricted Canada Post, PCCF, and PCCF+ data are rejected.

See:

- `CONTRIBUTING.md`
- `GOVERNANCE.md`
- `SECURITY.md`
- `docs/release-policy.md`
- `docs/license-attribution.md`
- `CITATION.cff`

OPCC is not affiliated with Canada Post or Statistics Canada and is not an
authoritative replacement for PCCF or PCCF+.
