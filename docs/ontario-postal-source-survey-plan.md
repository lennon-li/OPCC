# Ontario Postal-Code Source Survey Plan

## Project purpose

This repository will support development of an open, reproducible Ontario postal-code correspondence system inspired by the useful functions of PCCF/PCCF+, without copying or redistributing restricted Canada Post or licensed PCCF data.

The system should retrieve public data, preserve provenance, link postal-code observations to Statistics Canada geography, publish confidence and lineage, and allow community contributions.

## Core principle

A postal code is not treated as a polygon. The basic evidence unit is an observed relationship such as:

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

The eventual output should preserve many-to-many relationships between postal codes and dissemination blocks or dissemination areas.

## Ontario-only scope

The first survey and proof of concept are limited to Ontario. National datasets may be used only when they can be filtered to Ontario and materially improve Ontario coverage.

## Data required

### 1. Postal-code observations

Strongest forms of evidence:

1. postal code + civic address + coordinates
2. postal code + coordinates
3. postal code + civic address
4. civic address + coordinates, where postal code can be supplied from another open source
5. facility or business records used as validation anchors

### 2. Statistics Canada geography

Required for later linkage:

- dissemination-block digital boundaries
- dissemination-area boundaries
- Geographic Attribute File
- dissemination geography relationship files
- Census Forward Sortation Area boundaries for quality control
- Ontario municipal boundaries

### 3. Population and dwelling attributes

Population and dwelling counts are supporting attributes, not primary linkage evidence. Postal-to-geography weights should initially be driven by observed addresses or location evidence rather than splitting a dissemination block solely by population.

## Initial source list

### Priority 1: broad postal-code and address sources

1. **Statistics Canada Open Database of Addresses**
   - likely primary address-level evidence
   - inspect Ontario coverage, postal-code completeness, coordinates, provider lineage and vintage

2. **Statistics Canada National Address Register**
   - verify current status, latest release, Ontario fields and whether it has been superseded

3. **Ontario Data Catalogue: Canada Postal Code Data**
   - potentially useful but quarantined until resource-level licence and lineage are verified
   - determine whether any data originated from Canada Post, PCCF or another restricted product

4. **GeoNames Canadian postal-code file**
   - use as an approximate comparison layer and postal-code inventory
   - verify Ontario coverage, precision and update history

5. **OpenStreetMap Ontario extract**
   - supplementary contributed observations
   - retain as a licence-separated layer because of ODbL obligations

### Priority 2: Ontario municipal and regional address data

Prioritize direct portals and current machine-readable datasets for:

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
- other Ontario municipalities, counties and districts with civic-address data

For each source, determine whether the downloadable data contain:

```text
postal_code
civic_number
street_name
unit
municipality
latitude
longitude
building_id
property_id
address_status
last_updated
```

A civic-address dataset without postal codes remains useful for geocoding and reconciliation, but it is not direct postal-code evidence.

### Priority 3: public facility anchors

Survey Ontario datasets for:

- public and private schools
- colleges and universities
- licensed childcare centres
- hospitals
- long-term-care homes
- retirement homes
- community health centres
- pharmacies
- laboratories and specimen-collection centres
- mental-health and addiction services
- ServiceOntario locations
- libraries
- fire, police and paramedic stations
- courthouses
- government buildings
- airports and major transit terminals

These sources provide independently verifiable anchors and gap filling. They should not be interpreted as complete residential coverage.

### Priority 4: business and regulated-establishment sources

Potential sources include:

- Statistics Canada Open Database of Businesses
- municipal business-licence datasets
- food-premises inspection data
- tourism and accommodation registries
- regulated facility lists

## Source classification

Every source should receive one proposed role:

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

## Required source inventory fields

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

## Licence and provenance controls

A catalogue entry marked open is not sufficient evidence that the underlying data can be redistributed.

For every candidate source:

1. inspect the resource-level licence;
2. identify the original producer;
3. identify possible Canada Post or PCCF lineage;
4. separate portal metadata licensing from data licensing;
5. record attribution requirements;
6. flag ODbL, share-alike or database obligations;
7. quarantine unclear provenance;
8. reject restricted, scraped or non-reproducible sources.

Multiple republications of one municipal dataset must be treated as one source lineage, not independent corroboration.

## Minimum source inspection

For each accessible dataset:

1. retrieve a sample or complete file when practical;
2. inspect the actual schema;
3. normalize postal-code strings;
4. filter Ontario records;
5. calculate basic coverage statistics;
6. inspect random records, duplicates and outliers;
7. confirm coordinates fall within or near Ontario;
8. preserve evidence of licence and lineage.

Use this validation pattern:

```text
^[A-Z][0-9][A-Z][ ]?[0-9][A-Z][0-9]$
```

Normalize to `ANA NAN`. Regex validity does not prove that a postal code is active or correctly assigned.

## Proposed first proof-of-concept source set

Subject to verification:

1. Statistics Canada Open Database of Addresses, Ontario records
2. current municipal address sources that add newer or missing records
3. GeoNames as an approximate comparison layer
4. selected school, healthcare and public-facility datasets as anchors
5. OpenStreetMap as a separate supplementary layer with explicit ODbL handling
6. dissemination-block boundaries and the Geographic Attribute File for spatial linkage

The Ontario `Canada Postal Code Data` resource remains quarantined until its provenance and licence are conclusively verified.

## Planned outputs

```text
research/ontario-postal-source-inventory.csv
research/ontario-postal-source-survey.md
research/ontario-postal-municipal-coverage.csv
config/ontario-postal-source-manifest.yml
research/ontario-postal-source-decisions.md
```

Bulk downloaded data should not be committed to the repository.

## Future correspondence output

A first-generation correspondence table could contain:

```text
postal_code
DBUID
DAUID
n_observations
n_unique_addresses
n_sources
address_weight
best_link
confidence
source_vintage
census_vintage
```

Initial weights should be based primarily on observed address evidence. Population and dwelling counts may later support modelling, validation or effective-dwelling estimation.

## Completion standard for the survey

The source survey is complete when:

- every recommended source has a verified resource-level licence;
- every recommended source has a reproducible endpoint;
- actual schemas have been inspected;
- Ontario coverage has been measured;
- source lineages are documented;
- ambiguous and restricted sources are separated;
- the first-source manifest is sufficient to begin implementation without repeating discovery work.
