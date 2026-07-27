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

**Evidence and reason**: A 2026-07-27 screen confirmed the official City of
Ottawa `Address_Information/MapServer/0` layer. It is a public point service
with 403,080 records. All 403,080 records have non-null `POSTAL_CODE`,
`MUNICIPAL_ADDRESS_ID`, and `GLOBALID` values. The service can transform its
Web Mercator `SHAPE` geometry to EPSG:4326. Its metadata says address points
represent City properties and buildings and are placed either at parcel
centres or, for newer addresses, approximate building entrances. The latest
record-level creation and modification timestamps observed by aggregate query
were 2026-07-24.

The City of Ottawa Open Data Licence 2.0 permits copying, modification,
publication, and distribution with attribution. However, neither the service
metadata nor the licence identifies the upstream provenance of
`POSTAL_CODE`. Do not ingest, fixture, or implement this source until the City
confirms that the postal values are independently redistributable and are not
derived from Canada Post, PCCF, or PCCF+ material. If that is confirmed, use
`MUNICIPAL_ADDRESS_ID` as the source record identifier, preserve `GLOBALID`,
and derive longitude and latitude from transformed `SHAPE` geometry rather
than the undocumented `POINT_X` and `POINT_Y` fields.

## Other Ontario municipalities

**Decision**: `defer-verification`

**Evidence and reason**: The municipal coverage file records many sources as found while leaving postal fields and licences unverified. Those entries remain discovery leads only. Each requires an official catalogue URL, licence, endpoint, schema sample, postal completeness profile, geometry metadata, update date, and lineage note before acceptance.
