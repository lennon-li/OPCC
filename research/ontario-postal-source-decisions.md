# Ontario Postal Source Decisions

These decisions distinguish licence verification, source discovery, schema verification, profiling, and production readiness. A source is not ingestion-ready merely because an open-data catalogue entry exists.

## Decision vocabulary

- `accept-primary`: suitable for the primary proof of concept.
- `accept-supplementary`: usable only as a separate supporting source.
- `conditional-accept`: promising and openly licensed, but schema profiling is still required.
- `defer-validation`: retained for comparison, lineage, or tests rather than current production ingestion.
- `defer-verification`: source identity or schema is not sufficiently verified.
- `defer-separate-layer`: licence obligations require a separately designed output.
- `quarantine`: must not be ingested without explicit legal and provenance clearance.

## Statistics Canada National Address Register

**Decision**: `accept-primary`

**Evidence and reason**: Statistics Canada's current NAR release is dated June 26, 2026 and the product frequency is semi-annual. It provides valid georeferenced civic addresses and corresponding mailing-address information under the Open Government Licence - Canada. It is the best open national source for the first Ontario proof of concept.

**Caution**: describe its postal relationship as an `observed postal association`. Preserve release and lineage metadata and do not imply that the package recreates Canada Post's proprietary assignment process.

## Statistics Canada Open Database of Addresses

**Decision**: `defer-validation`

**Evidence and reason**: ODA is operationally superseded by NAR, but Ontario remains downloadable as a zipped CSV and includes postal code, provider, geographic identifiers, latitude, and longitude. It remains useful for historical comparisons, lineage analysis, schema prototyping, and regression tests.

## GeoNames Canadian Postal Codes

**Decision**: `accept-supplementary`

**Evidence and reason**: The full Canadian postal-code archive is available under CC BY 4.0. It is suitable as a separately retained point-reference layer.

**Caution**: the Ontario counts written in commit `a393382` are not reproducible from repository code and are therefore withdrawn pending profiling. Do not use GeoNames as address-level evidence or merge it into the primary source without explicit provenance fields.

## Ontario Data Catalogue "Canada Postal Code Data"

**Decision**: `quarantine`

**Evidence and reason**: The dataset is restricted and its relationship to licensed Canada Post or PCCF data is not established. It must not be downloaded, ingested, transformed, or redistributed as part of the open product without explicit clearance.

## OpenStreetMap Ontario

**Decision**: `defer-separate-layer`

**Evidence and reason**: OSM is openly available under ODbL, but database share-alike obligations require an intentional distribution and attribution design. It may later support a distinct optional layer, not the default combined database.

## Toronto One Address Repository

**Decision**: `conditional-accept`

**Evidence and reason**: The official City of Toronto catalogue entry is licensed under the Open Government Licence - Toronto and describes more than 500,000 authoritative address points in several spatial formats.

**Remaining gate**: verify the actual downloaded schema, six-character postal-code presence and completeness, stable resource endpoint, CRS, duplicate structure, release metadata, and checksum before ingestion.

## Ottawa Municipal Addresses

**Decision**: `defer-verification`

**Evidence and reason**: The initial survey asserted an authoritative address-to-postal-code source, but did not preserve a verified dataset identifier, schema sample, stable endpoint, row count, or postal-code completeness result. Re-evaluate from the official City of Ottawa catalogue before use.

## Other Ontario municipalities

**Decision**: `defer-verification`

**Evidence and reason**: The municipal coverage file records many sources as found while leaving postal fields and licences unverified. Those entries remain discovery leads only. Each requires an official catalogue URL, licence, endpoint, schema sample, postal completeness profile, geometry metadata, update date, and lineage note before acceptance.