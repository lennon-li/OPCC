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
  checksum = "<sha256 of the retrieved source file>"
)
layer <- build_source_layer(my_data, adapter)
profile_source_layer(layer)
bundle <- contribution_bundle(layer, output_dir = "contributions")
```

All calls announce that the layer remains local and invite contributions when
redistribution is permitted. Postal codes are normalized strictly. If supplied,
latitude and longitude must be paired, finite decimal-degree values within
their geographic bounds.

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
2026-07-19 GeoNames supplementary-point artifact. Its expected profile is
17,373 points: 17,334 with a 2021 Ontario DB/DA assignment and 39 retained as
explicitly unmatched. It is point reference evidence, not NAR address evidence.
