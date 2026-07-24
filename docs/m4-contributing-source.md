# M4 Source Adapters and Contributions

OPCC accepts open postal-code evidence as source-separated layers. A local
layer never modifies a canonical release, never overwrites NAR evidence, and
is not published until maintainers review its provenance and validation.

## Local workflow

```r
adapter <- new_source_adapter(
  source_id = "municipal_registry",
  licence = "Open Government Licence",
  lineage = "municipal address registry",
  retrieval_date = "2026-07-19",
  schema_map = list(postal_code = "postal", latitude = "lat", longitude = "lon"),
  endpoint = "https://example.org/open-data",
  checksum = "<sha256 of the retrieved source file>",
  location_type = "physical",
  coordinate_method = "address_point",
  authority_level = "municipal",
  coverage_type = "municipal_address_registry",
  update_frequency = "annual"
)
layer <- build_source_layer(my_data, adapter)
profile_source_layer(layer)
bundle <- contribution_bundle(layer, output_dir = "contributions")
```

All calls announce that the layer remains local and invite contributions when
redistribution is permitted. Every named `schema_map` entry is copied to its
normalized OPCC field before validation, while the original source fields
remain available for review. Core mappings include `postal_code`, `latitude`,
`longitude`, `address`, `source_record_id`, `municipality`, and
`source_vintage`; adapters may retain additional source-qualified fields.

Postal codes are normalized strictly. If supplied, latitude and longitude must
be paired, finite decimal-degree values within global geographic bounds. After
those checks, coordinate-bearing rows must fall within OPCC's inclusive broad
Ontario guardrail: latitude 41.6 to 56.9 and longitude -95.2 to -74.3. This
rectangle rejects clearly non-Ontario coordinates but does not prove provincial
membership; canonical candidate builds still require boundary and DB
intersection checks against separately pinned province and DB geometries.
`build_source_layer()` and `validate_source_data()` accept
`on_invalid = "error"`, `"drop"`, or `"quarantine"`. The default preserves the
original fail-fast behavior. Drop mode returns accepted rows only. Quarantine
mode also attaches rejected rows and their reasons as `opcc_quarantine`.
Out-of-guardrail rows include the reason `outside_ontario_bounds`.
Accepted output carries an `opcc_validation_report` attribute with input,
accepted, rejected, invalid-postal, missing-postal, invalid-coordinate, and
duplicate-evidence row counts, plus the specific
`outside_ontario_bounds_rows` count.

Adapter metadata distinguishes `location_type` (`physical`, `mailing`, or
`unknown`) from `coordinate_method` (`address_point`, `entrance`, `building`,
`parcel`, `centroid`, or `unknown`). It also records non-empty
`authority_level`, `coverage_type`, and `update_frequency` labels. These fields
default to `unknown` for backward compatibility and are written to contribution
provenance.

## Bundle contents

`contribution_bundle()` creates a deterministic, normalized fixture sample,
adapter configuration, quality report, and provenance declaration. The
provenance file records the licence, lineage, retrieval date, endpoint, schema
map, optional source checksum, and explicit `local_only: true` and
`canonical_release_modified: false` flags.

Attach the bundle to the **Source proposal** issue template. Maintainers check
the licence, endpoint, provenance, schema mapping, fixture, duplicate evidence,
coverage impact, and regression behavior before accepting an adapter or a new
release layer.

## Prohibited inputs

Do not submit Canada Post, PCCF, PCCF+, or any other restricted data. The M4
API rejects identifiers and provenance containing those restricted sources.

## Packaged example

`geonames_supplementary_adapter()` loads the checked metadata for the
published 2026-07-19 GeoNames supplementary-point artifact. Its published
profile is 17,373 points: 17,334 with a 2021 Ontario DB/DA assignment and 39
with missing DB/DA identifiers. Future canonical candidates must revalidate
those points against the separately pinned Ontario polygon and publish explicit
`db_match_status` values rather than preserving the historical count by
assumption. It is point reference evidence, not NAR address evidence.
