# Ontario Postal-Code Source Survey

## Status

This document is a verified correction of the initial survey committed in `a393382`. The first pass established a useful structure, but several source claims were stronger than the evidence supported. This revision separates confirmed facts from work that still requires reproducible profiling.

## Executive Summary

The strongest open starting point is Statistics Canada's National Address Register (NAR). The current release is dated June 26, 2026, the product is semi-annual, and it contains valid georeferenced civic addresses with corresponding mailing-address fields. NAR should be treated as the primary source of observed address-to-postal-code associations, not as a public clone of PCCF.

The Open Database of Addresses (ODA) should not be discarded. It is older and superseded operationally by NAR, but remains useful for lineage analysis, schema prototyping, regression tests, and comparison with the contributing municipal datasets.

GeoNames is openly licensed and useful as a supplementary postal-code point reference. The previous Ontario record counts have not been reproduced in this repository and must not be treated as verified until a profiling script records the download date, checksum, row counts, unique postal codes, province filter, and validation rules.

Toronto has an authoritative open address-point dataset with more than 500,000 address points and multiple downloadable spatial formats. Its postal-code field and completeness still require direct schema profiling. Ottawa and all other municipalities remain discovery candidates rather than ingestion-ready sources until their exact catalogue records, endpoints, licences, schemas, and row-level postal evidence are verified.

## Verified Findings

### Statistics Canada National Address Register

- Catalogue number: `46-26-0002`.
- Current release: June 26, 2026.
- Frequency: semi-annual.
- Scope: valid georeferenced civic addresses and corresponding mailing-address information.
- Provenance: addresses are extracted from Statistics Canada's Building Register and validated using at least two independent sources.
- Recommended role: primary observed address and postal-association source.
- Important limitation: the mailing address follows Canada Post addressing guidelines, but the project must preserve source lineage and must not describe the field as an independently reconstructed Canada Post assignment.

### Statistics Canada Open Database of Addresses

- Open Government Licence - Canada.
- Ontario remains available as a downloadable provincial zipped CSV.
- Includes postal code, provider, CSD identifiers, latitude, and longitude.
- Aggregates many local-government open datasets.
- Recommended role: validation-only, lineage analysis, historical comparison, and test fixture development.

### GeoNames Canadian Postal Codes

- `CA_full.csv.zip` contains full Canadian postal codes.
- Licence: Creative Commons Attribution 4.0.
- Recommended role: supplementary centroid or reference layer only.
- Current repository status: licence and file existence verified; Ontario counts and quality metrics unverified.

### Toronto One Address Repository

- Official City of Toronto open-data catalogue entry exists.
- Licence: Open Government Licence - Toronto.
- Described as containing more than 500,000 address points.
- Available in CSV, GeoJSON, GeoPackage, and shapefile forms, including EPSG:4326 resources.
- Recommended role: authoritative local address geometry after schema profiling.
- Current repository status: catalogue and licence verified; postal-code field, missingness, duplicates, and stable resource URL not yet verified.

## Findings Not Yet Verified

The initial survey marked Ottawa and fourteen additional municipalities as having address sources, but did not record enough evidence to support that status. Each municipality must have all of the following before being promoted to ingestion-ready:

1. official catalogue URL;
2. stable download or API endpoint;
3. explicit licence URL;
4. sampled field names;
5. confirmation of full six-character postal codes;
6. geometry type and coordinate reference system;
7. release or update date;
8. row count and postal-code completeness;
9. provenance and known upstream lineage.

Until then, their status is `discovered_unverified`, not `accepted`.

## Licensing and Lineage Rules

- Never ingest restricted Ontario postal-code data or licensed PCCF/Canada Post products.
- Treat NAR, ODA, and municipal sources as potentially overlapping lineages.
- Agreement between overlapping lineage sources is not independent corroboration.
- Keep OpenStreetMap-derived products separate because ODbL database obligations require a deliberate distribution design.
- Preserve source-level observations rather than collapsing immediately to one postal-code point.
- Use the phrase `observed postal association` unless the source explicitly establishes assignment authority.

## Revised Source Decisions

| Source | Decision | Intended use |
|---|---|---|
| Statistics Canada NAR | accept-primary | Primary address and observed postal associations |
| Statistics Canada ODA | defer-validation | Historical comparison, lineage, tests |
| GeoNames CA full | accept-supplementary | Reference points and gap diagnostics after profiling |
| Toronto One Address Repository | conditional-accept | Local authoritative geometry after schema profiling |
| Ottawa municipal addresses | defer-verification | Do not ingest until exact source and schema are confirmed |
| Other Ontario municipal sources | discovery-required | Complete source-by-source verification |
| Ontario restricted postal data | quarantine | No ingestion or redistribution |
| OpenStreetMap Ontario | defer-separate-layer | Optional independent ODbL product only |

## Recommended First Technical Milestone

Build a reproducible profiling pipeline before building the full linkage product. It should:

1. download the current NAR release and Ontario subset;
2. record URL, release date, checksum, file size, and schema;
3. profile mailing postal-code completeness and validity;
4. spatially assign observations to current Dissemination Blocks;
5. use the Geographic Attribute File to derive higher geographies;
6. profile ODA Ontario as a historical comparison;
7. profile GeoNames separately without mixing it into the primary observation table;
8. profile Toronto as the first municipal source;
9. output source-level quality and lineage reports.

## Implementation Gate

The project is ready for a narrow NAR profiling proof of concept. It is not yet ready for a province-wide multi-source production build. The next gate is passed only when the NAR download, Ontario extraction, schema, postal-code metrics, DB assignment, and provenance output are reproducible from code.