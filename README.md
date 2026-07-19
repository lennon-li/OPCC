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

M1 is complete. The verified NAR 2026-06-26 M2 baseline contains 414,207
postal-code/DBUID rows covering 282,409 postal codes under
`releases/m2/2026-06-26/`. M2 is being amended to include 17,334
GeoNames-sourced point-to-DB/DA assignments as a separate supplementary
evidence class. The remaining 39 of the 17,373 GeoNames points do not
intersect a 2021 Ontario DB/DA and remain visible in M1 rather than receiving
a fabricated link. The independently rebuilt amendment contains 431,541 rows
covering 299,743 postal codes; the immutable baseline will not be overwritten.

The M1 reference layer retains all 17,373 GeoNames-sourced fallback points.
The 17,334 that intersect a DB/DA are M2 supplementary evidence; the other 39
remain explicitly unmatched. These records are not silently treated as NAR
address evidence, and their GeoNames accuracy category remains source metadata
rather than a probability or confidence score.

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
