# OPCC

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

## Install and use

```r
remotes::install_github("lennon-li/OPCC")

library(OPCC)

# Direct postal-code-to-DA lookup
pc_to_geo("K1A 0A6", level = "DA")

# Retain every defensible DB link and its allocation weight
pc_to_geo("M5V 3A8", level = "DB", all_links = TRUE)

# Inspect the source-qualified point evidence
pc_to_point("K1A 0A6")
```

Lookup results preserve source class and vintage. Multiple links remain visible
by default. Selecting one link is explicit, and unmatched postal codes remain
reported rather than receiving a fabricated assignment.

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

CRAN submission work and independent external validation are intentionally
tracked separately from the completed product milestones.

## Verify a release

From a source checkout:

```bash
Rscript scripts/m3_validate_release.R
Rscript scripts/m3_validate_release.R --remote
```

The validator checks commit-pinned artifacts and manifests against SHA-256
hashes, then verifies schema and correspondence invariants, including unique
keys, allocation-weight sums, and one deterministic `best_link` per covered
postal code.

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

## Rebuild

Large public inputs are downloaded to `.scratch/` and are not committed. A
candidate build can be reproduced with the documented source manifests,
checksums, census boundaries, and GAF inputs:

```bash
Rscript scripts/m1_nar_profile.R
Rscript scripts/m4_geonames_profile.R
Rscript scripts/m1_build_centroids.R
Rscript scripts/m1_gaf_rollup.R
Rscript scripts/m2_build_correspondence.R
```

See `docs/m1-reproduction.md`, `docs/m2-reproduction.md`, and
`docs/reproduce-m2-artifact.qmd` for detailed instructions.

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