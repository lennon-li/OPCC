# Source Decisions

## Statistics Canada National Address Register
**Decision**: `accept`
**Evidence and Reason**: Authoritative federal open address dataset with valid Open Government Licence. It is the current standard, superseding the ODA. Provides direct postal evidence.

## Statistics Canada Open Database of Addresses (ODA)
**Decision**: `reject`
**Evidence and Reason**: Superseded and archived in favor of the National Address Register. Using it would duplicate NAR lineages with outdated data.

## GeoNames Canadian Postal Codes
**Decision**: `accept`
**Evidence and Reason**: Provides 298,607 valid point locations for Ontario postal codes. License is CC BY 4.0. Will be used as a supplementary layer for gap-filling and baseline comparisons.

## Ontario Data Catalogue "Canada Postal Code Data"
**Decision**: `quarantine`
**Evidence and Reason**: Listed as restricted on the Ontario Data Catalogue. Provenance and derivation from Canada Post PCCF are unclear and require manual legal review before any use.

## OpenStreetMap Ontario
**Decision**: `defer`
**Evidence and Reason**: Valid open data (ODbL) with good coverage, but the share-alike obligations risk contaminating the primary dataset. Must be kept completely separate. Deferred from the initial proof-of-concept build.

## Toronto Address Points
**Decision**: `accept`
**Evidence and Reason**: Authoritative municipal source with clear Open Government Licence. Contains direct address-to-postal-code linkages.

## Ottawa Municipal Addresses
**Decision**: `accept`
**Evidence and Reason**: Authoritative municipal source with clear Open Government Licence. Contains direct address-to-postal-code linkages.
