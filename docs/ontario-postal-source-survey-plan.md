# Ontario Postal-Code Source Survey Plan

## Status (updated 2026-07-17)

The survey this plan commissioned has been executed and revised once. All five
planned output files exist (see "Planned outputs"), and the corrected findings
live in `research/ontario-postal-source-survey.md` and
`research/ontario-postal-source-decisions.md`. Where this plan and those files
disagree, the research files win; this plan is kept current only at the level
of scope, principles, and next milestone.

Key changes since the plan was written:

1. **Primary source reversed.** The plan expected the Open Database of
   Addresses (ODA) to be the primary evidence source. Verification showed the
   National Address Register (NAR, catalogue `46-26-0002`, release 2026-06-26,
   semi-annual) supersedes it. NAR is now `accept-primary`; ODA is
   `defer-validation` (lineage analysis, regression tests, historical
   comparison).
2. **Decision vocabulary upgraded.** The simple accept/quarantine/reject/defer
   set was replaced by the seven-value vocabulary defined in
   `research/ontario-postal-source-decisions.md` (`accept-primary`,
   `accept-supplementary`, `conditional-accept`, `defer-validation`,
   `defer-verification`, `defer-separate-layer`, `quarantine`).
3. **First-pass claims withdrawn.** GeoNames Ontario counts and the Ottawa
   source assertion from the initial survey commit (`a393382`) were not
   reproducible and are withdrawn pending profiling. Nothing is
   ingestion-ready until a committed profiling script reproduces its metrics.

Survey work still outstanding (the completion standard below is NOT yet met):

- **Municipal discovery.** Only Toronto is verified at catalogue/licence
  level; Ottawa and 14 others are `discovery_required`/`defer-verification`.
  The coverage file also omits Frontenac, Leeds and Grenville, and Renfrew
  from the planned Priority 2 list.
- **Priority 3 and 4 were not surveyed.** No facility-anchor or
  business/regulated-establishment sources appear in the inventory yet.
- **Supporting geography endpoints not documented.** Dissemination-block/-area
  boundaries, the Geographic Attribute File, relationship files, FSA
  boundaries, and municipal boundaries still need verified retrieval
  endpoints recorded.

**Next milestone (implementation gate):** a reproducible NAR profiling proof
of concept - download the current NAR release, extract Ontario, record URL,
checksum, schema and release metadata, profile postal-code completeness and
validity, assign observations to Dissemination Blocks, and derive higher
geographies via the Geographic Attribute File. The project is not ready for a
province-wide multi-source build until that pipeline is reproducible from
code. Secondary profiling targets, in order: ODA Ontario (comparison),
GeoNames (separate layer), Toronto One Address Repository (first municipal).

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

1. **Statistics Canada National Address Register** - VERIFIED, `accept-primary`
   - catalogue `46-26-0002`, release 2026-06-26, semi-annual, OGL-Canada
   - primary source of observed address-to-postal associations
   - profiling (endpoint, checksum, Ontario metrics) still pending

2. **Statistics Canada Open Database of Addresses** - VERIFIED, `defer-validation`
   - superseded operationally by NAR; retained for lineage analysis, schema
     prototyping, regression tests and historical comparison

3. **Ontario Data Catalogue: Canada Postal Code Data** - `quarantine` (confirmed)
   - restricted; possible Canada Post / PCCF lineage not cleared
   - do not download, ingest, transform or redistribute without explicit clearance

4. **GeoNames Canadian postal-code file** - VERIFIED licence, `accept-supplementary`
   - CC BY 4.0; `CA_full.csv.zip` endpoint confirmed
   - first-pass Ontario counts withdrawn; profile with recorded checksum,
     province filter, row and unique-code counts before use

5. **OpenStreetMap Ontario extract** - `defer-separate-layer`
   - ODbL obligations require a deliberately designed separate product
   - never merged into the default combined database

### Priority 2: Ontario municipal and regional address data

Status 2026-07-17: Toronto (One Address Repository) is `conditional-accept`
with catalogue and licence verified but schema profiling pending. Ottawa is
`defer-verification` (first-pass evidence not reproducible). All others below
remain `discovery_required` - see
`research/ontario-postal-municipal-coverage.csv`.

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

Every source receives one proposed role:

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

In addition, every surveyed source receives one decision from the vocabulary
defined in `research/ontario-postal-source-decisions.md`:

```text
accept-primary
accept-supplementary
conditional-accept
defer-validation
defer-verification
defer-separate-layer
quarantine
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

Revised 2026-07-17 after verification:

1. Statistics Canada National Address Register, Ontario records (primary)
2. Statistics Canada Open Database of Addresses, Ontario records
   (historical comparison and lineage only)
3. GeoNames as a separately profiled reference layer
4. Toronto One Address Repository, once schema profiling passes
5. dissemination-block boundaries and the Geographic Attribute File for
   spatial linkage (endpoints still to be documented)

Deferred beyond the first proof of concept: other municipal sources
(discovery incomplete), facility and business anchors (not yet surveyed),
and OpenStreetMap (separate ODbL layer by design).

The Ontario `Canada Postal Code Data` resource remains quarantined until its provenance and licence are conclusively verified.

## Planned outputs

All delivered (initial pass `a393382`, corrected pass 2026-07-17):

```text
research/ontario-postal-source-inventory.csv
research/ontario-postal-source-survey.md
research/ontario-postal-municipal-coverage.csv
config/ontario-postal-source-manifest.yml
research/ontario-postal-source-decisions.md
```

These files are the live record; this plan does not restate their contents.

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

Standing 2026-07-17: licences verified for NAR, ODA, GeoNames, Toronto and
OSM; ambiguous/restricted sources separated (Ontario PCD quarantined).
Not yet met: reproducible ingestion endpoints for NAR and Toronto, schema
inspection of actual downloads, measured Ontario coverage (all
`profile_status: pending` in the manifest), facility/business anchor survey,
and supporting-geography endpoints. These are closed by the NAR profiling
milestone and a follow-up discovery pass, not by further document edits.
