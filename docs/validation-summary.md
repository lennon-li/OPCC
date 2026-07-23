# OPCC Validation Summary

OPCC combines checksum-bound release assurance, deterministic invariants,
synthetic pipeline tests, and a maintainer-run comparison against an external
licensed reference. The evidence supports the published claims below; it does
not make OPCC authoritative or independently certified.

## External-reference evidence

M5 release `2026-07-20` was compared with a licensed, PCCF-derived Ontario DA
export from March 2023. Both use 2021 census geography. The comparison covered
280,649 postal codes present in both datasets.

| Measure | Result |
| --- | ---: |
| Reference codes covered by OPCC | 95.98% |
| OPCC codes covered by the reference | 99.38% |
| Any-link agreement / pair recall | 99.46% |
| OPCC best-link contained in reference | 95.65% |
| Exact-set agreement | 91.83% |
| Pair precision | 88.97% |
| Pair F1 | 93.92% |

The reference provides one DA link per postal code. OPCC deliberately retains
additional defensible candidate links, so pair precision and exact-set
agreement penalize those additional links. The best-link containment measure
asks whether OPCC's selected DA occurs in the external reference set; it does
not invent a reference-side probability or winner.

The reference is March 2023 and OPCC's source evidence is June 2026.
Disagreements can therefore reflect postal assignment change between vintages
as well as OPCC error. The reference has no coordinates or DBUID field, so this
comparison validates M5 DA correspondence only. M1 coordinate accuracy and M2
DB correspondence remain without an empirical PCCF comparison.

The public, aggregate-only evidence is recorded in
[`pccf-da-2023-public-attestation.json`](validation/pccf-da-2023-public-attestation.json).
No licensed row values, workbook hash, private-output hash, or local path is
published.

## Release and pipeline assurance

OPCC also applies the following controls:

- SHA-256 verification of indexed artifacts and manifests before use;
- exact M5-to-M2 parent-artifact and parent-manifest ancestry checks;
- schema, Ontario identifier, unique-pair, allocation-weight, and exactly-one
  deterministic `best_link` invariants;
- Ontario coordinate bounds, exact Ontario boundary membership, and 2021 DB
  assignment safeguards for point evidence;
- byte-for-byte verification that executed validation code matches its
  attributed producer commit;
- aggregate-output allowlists, path isolation, canary leak tests, and
  synthetic PCCF-shaped fixtures;
- deterministic synthetic M1 benchmarking that exercises the point-validation
  machinery but is explicitly not empirical accuracy evidence.

Reproduction and implementation details:

- [`validation_reproduction.md`](validation_reproduction.md)
- [`m1-reproduction.md`](m1-reproduction.md)
- [`m2-reproduction.md`](m2-reproduction.md)
- [`m5-reproduction.md`](m5-reproduction.md)
- [`m6-release-system.md`](m6-release-system.md)
- [`scripts/pccf_da_validate.R`](../scripts/pccf_da_validate.R)
- [`config/pccf-da-validation-contract.example.json`](../config/pccf-da-validation-contract.example.json)

Third-party validation remains future work. This completed comparison is a
maintainer-run external-reference benchmark, not an independent audit.
