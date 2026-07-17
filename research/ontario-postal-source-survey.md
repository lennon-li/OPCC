# Ontario Postal-Code Source Survey

## Executive Summary
This survey identified and evaluated public datasets containing postal-code evidence for Ontario. We prioritized sources based on open licensing, authoritative provenance, and direct location evidence (coordinates + address + postal code). The primary finding is that the Statistics Canada National Address Register (NAR) should serve as the primary source, replacing the deprecated Open Database of Addresses (ODA). GeoNames provides a strong supplementary dataset, while the Ontario Data Catalogue's "Canada Postal Code Data" is restricted and must be quarantined.

## Strongest Usable Sources
1. **Statistics Canada National Address Register (NAR)**: The most comprehensive and authoritative source of validated civic addresses in Canada.
2. **GeoNames Canadian Postal Codes**: Contains 298,607 valid Ontario records with point coordinates. Lacks civic addresses but provides excellent baseline coverage.
3. **Municipal Open Data Portals**: Toronto and Ottawa offer highly accurate, locally authoritative address points with open licenses.

## Measured or Estimated Ontario Coverage
- **GeoNames**: 298,607 valid Ontario postal code point locations.
- **NAR/Municipal**: Provides millions of address points, though exact postal-code completeness varies by municipality.

## Major Geographic Gaps
Rural and unorganized territories in Northern Ontario have weaker civic addressing, relying more heavily on PO Boxes and general delivery, which do not link well to specific building coordinates.

## Licensing Risks
- **OpenStreetMap (OSM)**: Uses the ODbL license, which has a share-alike clause. Any dataset merging OSM data with other data risks triggering share-alike obligations for the entire combined dataset. OSM data must be maintained as a separate, distinct layer.
- **PCCF/Canada Post Contamination**: Several provincial and federal datasets may have derived their postal code assignments from Canada Post's proprietary PCCF. We must ensure selected data comes from independent municipal assignment or open crowdsourcing.

## Stale, Retired or Inaccessible Sources
- **Statistics Canada Open Database of Addresses (ODA)**: Succeeded by the NAR.
- **Ontario Data Catalogue "Canada Postal Code Data"**: Restricted access.

## Duplicated Source Lineages
The ODA was largely an aggregation of municipal open data. Using both the ODA/NAR and the direct municipal datasets (e.g., from Toronto or Ottawa) constitutes duplicated source lineages rather than independent corroboration.

## Recommended First Ingestion Set
1. Statistics Canada National Address Register (NAR)
2. Toronto Address Points (Municipal)
3. Ottawa Municipal Addresses (Municipal)
4. GeoNames (Supplementary layer)

## Sources Requiring Human or Legal Review
- **Ontario Data Catalogue "Canada Postal Code Data"**: Need to confirm why it is restricted and if an open version with clear provenance exists.

## Rejected Sources and Reasons
- **Statistics Canada Open Database of Addresses (ODA)**: Rejected because it is superseded by the NAR.

## Update-Check Mechanism for Each Selected Source
- **NAR**: Check Statistics Canada catalogue page for new release vintages (annual).
- **GeoNames**: HTTP headers (`Last-Modified`, `ETag`) on the `CA_full.csv.zip` URL.
- **Municipal**: ArcGIS Hub API metadata (`updatedAt`) or CKAN datastore API metadata.
