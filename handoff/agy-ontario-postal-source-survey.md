# Agy Handoff: Survey Public Ontario Postal-Code Sources

## Objective

Conduct a comprehensive but tightly scoped survey of publicly accessible datasets that can contribute evidence connecting six-character postal codes to addresses, coordinates, buildings or geographic locations in Ontario.

This is source research and assessment only. Do not build the production ingestion pipeline yet.

## Project context

The repository aims to support an open, reproducible Ontario postal-code correspondence system inspired by useful PCCF/PCCF+ functions without copying or redistributing restricted Canada Post or licensed PCCF data.

A postal code is not assumed to have an exclusive polygon. The target evidence unit is:

```text
postal_code
address
latitude
longitude
source
source_record_id
source_release_date
retrieval_date
licence
precision
```

The eventual product must preserve many-to-many relationships between postal codes and dissemination blocks or dissemination areas.

Read first:

```text
docs/ontario-postal-source-survey-plan.md
```

## Geographic scope

Ontario only.

National datasets may be included only when they can be filtered to Ontario and materially contribute Ontario observations.

## Survey order

### Category A: direct postal-code location evidence

Find datasets containing:

```text
postal_code + latitude + longitude
```

Initial candidates:

- Statistics Canada Open Database of Addresses
- Statistics Canada National Address Register
- Ontario Data Catalogue `Canada Postal Code Data`
- GeoNames Canadian postal-code file
- OpenStreetMap Ontario extract

### Category B: address-level postal-code evidence

Find datasets containing:

```text
postal_code + civic address
```

Coordinates may or may not be present.

Initial candidates:

- provincial facility and building registries
- public- and private-school contact data
- long-term-care-home listings
- retirement-home listings
- hospital and health-service directories
- childcare-centre listings
- government office and building inventories
- municipal business-licence datasets

### Category C: municipal and regional civic-address sources

Identify current address-point or civic-address datasets from Ontario municipalities, regions and counties.

Prioritize:

- Toronto
- Ottawa
- Peel
- York
- Durham
- Halton
- Hamilton
- Waterloo
- Niagara
- London and Middlesex
- Windsor and Essex
- Kingston
- Simcoe
- Greater Sudbury
- Thunder Bay
- Peterborough
- Frontenac
- Leeds and Grenville
- Renfrew
- other municipalities or districts with province-scale relevance

For every source, verify whether the actual downloadable resource contains postal codes. Do not infer this from a title or catalogue description.

### Category D: facility and business anchors

Survey:

- Statistics Canada Open Database of Healthcare Facilities
- Statistics Canada Open Database of Businesses
- Ontario Ministry of Health service-provider locations
- hospitals
- long-term-care homes
- retirement homes
- pharmacies
- schools and school boards
- childcare facilities
- municipal business licences
- libraries
- fire, police and paramedic stations
- courthouses
- government buildings
- ServiceOntario locations
- transit terminals and airports

These are validation and gap-filling anchors, not substitutes for residential-address coverage.

### Category E: supporting geography

Confirm current authoritative retrieval endpoints for:

- 2021 dissemination-block digital boundaries
- 2021 dissemination-area boundaries
- 2021 Geographic Attribute File
- 2021 dissemination geography relationship files
- 2021 Census Forward Sortation Area boundaries
- Ontario municipal boundaries

Document these but do not classify them as postal-code sources.

## Required assessment fields

Create one record per candidate source with:

```text
source_id
source_name
publisher
jurisdiction
coverage
source_category
catalogue_page
download_endpoint
api_endpoint
access_method
file_format
licence_name
licence_url
redistribution_allowed
attribution_required
share_alike_or_database_obligation
postal_code_present
postal_code_field
postal_code_level
address_present
coordinate_present
geometry_type
coordinate_reference_system
unit_or_suite_present
building_or_property_id_present
status_field_present
release_date
last_updated
expected_update_frequency
record_count
ontario_record_count
distinct_ontario_postal_codes
valid_postal_code_count
invalid_postal_code_count
missing_postal_code_rate
duplicate_rate
source_lineage
known_limitations
proposed_role
priority
verification_status
notes
```

Use these `proposed_role` values:

```text
primary
authoritative_local
supplementary
facility_anchor
validation_only
supporting_geography
quarantined
rejected
```

## Licence and provenance controls

Do not assume that a catalogue record marked open makes the underlying data safe to redistribute.

For every source:

1. inspect the resource-level licence;
2. identify the original producer;
3. identify whether Canada Post, PCCF or another licensed product is in the lineage;
4. distinguish portal metadata licensing from the actual data licence;
5. record attribution requirements;
6. flag ODbL, share-alike or database obligations;
7. flag ambiguous or missing provenance.

Pay particular attention to Ontario Data Catalogue entries named `Canada Postal Code Data` and `Postal Code Data`. Determine whether the apparently open resource is genuinely independent and redistributable.

Do not download, store or redistribute restricted PCCF or Canada Post licensed data.

## Minimum source inspection

For each accessible dataset:

1. retrieve a small sample or complete file when practical;
2. inspect the actual schema;
3. normalize candidate postal-code strings;
4. filter Ontario records;
5. calculate basic coverage statistics;
6. inspect ten randomly selected records;
7. inspect ten duplicated postal codes;
8. inspect obvious coordinate and formatting outliers;
9. confirm coordinates fall within or near Ontario;
10. preserve evidence of the licence and source lineage.

Validate candidate postal-code strings with:

```text
^[A-Z][0-9][A-Z][ ]?[0-9][A-Z][0-9]$
```

Normalize to `ANA NAN`. Regex validity is not proof that a postal code is active or correctly assigned.

## Municipal survey strategy

Do not search every municipality without structure.

1. Extract Ontario source providers from Statistics Canada's Open Database of Addresses metadata.
2. Check each original provider for a newer direct release.
3. Add major municipalities and upper-tier governments that are absent.
4. Search ArcGIS Hub, CKAN, Socrata and municipal open-data portals.
5. Record retired, replaced and inaccessible datasets.
6. Prefer machine-readable APIs or stable downloads.
7. Record whether updates can be checked automatically using ETag, Last-Modified, API metadata or release identifiers.

## Source-lineage rule

Do not merge or deduplicate source records during this task.

Several catalogues may reproduce the same original municipal data. Record lineage so these copies are not later counted as independent evidence.

Example:

```text
municipal original
    -> Statistics Canada harmonized database
    -> another federal or provincial republication
```

This is one underlying source lineage, not three independent observations.

## Deliverables

Create these files:

### 1. `research/ontario-postal-source-inventory.csv`

One row per candidate source with all required fields.

### 2. `research/ontario-postal-source-survey.md`

Include:

- executive summary
- strongest usable sources
- measured or estimated Ontario coverage
- major geographic gaps
- licensing risks
- stale, retired or inaccessible sources
- duplicated source lineages
- recommended first ingestion set
- sources requiring human or legal review
- rejected sources and reasons
- update-check mechanism for each selected source

### 3. `research/ontario-postal-municipal-coverage.csv`

Include:

```text
municipality_or_region
population_priority
address_source_found
postal_code_present
coordinates_present
latest_release
licence_verified
source_id
coverage_status
notes
```

Use these coverage statuses:

```text
direct_postal_evidence
address_only
facility_only
approximate_only
no_source_found
unverified
```

### 4. `config/ontario-postal-source-manifest.yml`

Include only sources recommended for the first proof-of-concept build.

Do not include a source until its endpoint, schema, licence and lineage are verified.

### 5. `research/ontario-postal-source-decisions.md`

For each source, record one decision:

```text
accept
quarantine
reject
defer
```

State the evidence and reason.

## Decision criteria

### Accept as primary

- explicit open licence
- clear original provenance
- postal code and coordinates or a geocodable address
- machine-readable access
- meaningful Ontario coverage
- reproducible retrieval
- no evidence of Canada Post or PCCF licensing contamination

### Accept as supplementary

- valid open licence
- partial geographic or entity coverage
- useful independent observations
- limitations can be represented in metadata

### Quarantine

- apparently open but unclear lineage
- licence attached only to catalogue metadata
- possible derivation from PCCF or Canada Post data
- no clear right to redistribute
- unexplained national postal-code completeness

### Reject

- restricted or commercial licence
- scraped from a prohibited service
- non-reproducible access
- no defensible provenance
- terms prohibit storage, bulk retrieval or redistribution
- apparent unauthorized copy of licensed postal data

## Expected final recommendation

Recommend a small initial ingestion set, not every discovered source.

The likely candidates to test are:

1. Statistics Canada Open Database of Addresses, Ontario subset
2. verified current municipal address sources that add newer or missing records
3. GeoNames as an approximate comparison layer
4. selected Ontario school, healthcare and public-facility datasets as anchors
5. OpenStreetMap as a separate supplementary layer subject to ODbL handling
6. Statistics Canada dissemination-block boundaries and Geographic Attribute File for later spatial overlay

Keep Ontario `Canada Postal Code Data` quarantined until provenance and licence are conclusively verified.

## Completion standard

The survey is complete only when:

- every recommended source has a verified resource-level licence;
- every recommended source has a reproducible endpoint;
- actual data fields have been inspected;
- source lineage is documented;
- Ontario coverage has been measured;
- restricted and ambiguous sources are separated;
- the first-source manifest can begin implementation without repeating discovery work.

## Repository and workflow constraints

- Do not commit bulk downloaded data.
- Do not create a new branch.
- Do not create a pull request.
- Update the research files as findings are verified.
- Do not commit or push without Lennon's explicit approval.
