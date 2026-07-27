# Ottawa Municipal Address Source Screen

Screen date: 2026-07-27

Decision: `defer-verification`

## Official sources

- City service:
  `https://maps.ottawa.ca/arcgis/rest/services/Address_Information/MapServer/0`
- City service metadata:
  `https://maps.ottawa.ca/arcgis/rest/services/Address_Information/MapServer/info/iteminfo`
- City licence:
  `https://ottawa.ca/en/city-hall/open-transparent-and-accountable-government/open-data/open-data-licence-version-20`

The service is publicly accessible without authentication. The City licence
permits copying, modifying, publishing, adapting, and distributing the
information for lawful purposes, including commercially, subject to
attribution. OPCC's attribution would be:

> Contains information licensed under the Open Government Licence - City of
> Ottawa.

## Confirmed service contract

The official layer is `Municipal Address / Points d'adresse municipaux`, a
point feature layer covering City of Ottawa properties and buildings.

The live screen confirmed:

- 403,080 records;
- 403,080 non-null `POSTAL_CODE` values;
- 403,080 non-null `MUNICIPAL_ADDRESS_ID` values;
- 403,080 non-null `GLOBALID` values;
- a six-character `POSTAL_CODE` field;
- `FULL_ADDRESS_EN` and `FULL_ADDRESS_FR`;
- `MUNICIPAL_ADDRESS_ID`, `GLOBALID`, and related road identifiers;
- `CREATED_DATE` and `MODIFIED_DATE`;
- source geometry in EPSG:3857;
- server-side geometry transformation to EPSG:4326;
- latest aggregate record timestamp of 2026-07-24 20:33:30 UTC.

The service metadata states that points are placed at either the parcel centre
or, for newer addresses, the approximate building entrance. The adapter
metadata therefore cannot claim one uniform coordinate method. A future
accepted adapter should use `unknown` as its row-level coordinate method unless
the City supplies a field or rule that distinguishes the two placements.

## Proposed adapter mapping after acceptance

This mapping is design evidence only. It is not an accepted or packaged
adapter.

| OPCC field | City field or derivation |
| --- | --- |
| `postal_code` | `POSTAL_CODE` |
| `latitude` | transformed `SHAPE.y` in EPSG:4326 |
| `longitude` | transformed `SHAPE.x` in EPSG:4326 |
| `address` | `FULL_ADDRESS_EN` |
| `source_record_id` | `MUNICIPAL_ADDRESS_ID` |
| `municipality` | City of Ottawa, retaining source `MUNICIPALITY` separately |
| `source_vintage` | retrieval date plus record dates |

Preserve `GLOBALID` as additional lineage. Do not use `OBJECTID` as a stable
identifier. Do not use `POINT_X` or `POINT_Y`: their units and derivation are
not documented by the layer metadata.

## Blocking evidence

The City service documents the existence and completeness of `POSTAL_CODE` but
does not document where those values originate. The Open Data Licence does not
grant rights over third-party information that the City is not authorized to
license.

Before OPCC ingests, fixtures, redistributes, or implements this source, obtain
written confirmation from the City that:

1. `POSTAL_CODE` is independently redistributable under the City licence;
2. it is not derived from Canada Post, PCCF, or PCCF+ material;
3. `MUNICIPAL_ADDRESS_ID` is intended to remain stable across refreshes;
4. the public service's update cadence or release policy is documented.

Until then, the source remains `defer-verification`. No Ottawa adapter, fixture,
or canonical data change is authorized by this screen.
