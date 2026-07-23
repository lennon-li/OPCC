# M1 PoC Reproduction Guide (NAR Profiling & GAF Rollup)

This document provides instructions and URLs necessary to reproduce the M1 milestone (the National Address Register profiling, DB spatial assignment, and Geographic Attribute File rollup) from scratch.

## 1. Required Source Data

To run the pipeline, the following external, authoritative datasets must be downloaded:

### A. Statistics Canada 2021 Province/Territory Boundary File
* **Format Required:** ArcGIS Shapefile (`.shp`)
* **Purpose:** Provides the independent Ontario jurisdiction polygon used to
  reject points outside the province before DB assignment.
* **Source:** Statistics Canada, 2021 Census digital boundary files.
* **Download URL:** [https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lpr_000b21a_e.zip](https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lpr_000b21a_e.zip)
* **Local Path (Git-ignored):** Extract to `.scratch/shp/`

### B. Statistics Canada 2021 Dissemination Block (DB) Boundary Files
* **Format Required:** ArcGIS Shapefile (`.shp`)
* **Purpose:** Provides the spatial polygons needed to assign each postal centroid coordinate to a specific Dissemination Block (DB) via a point-in-polygon spatial join (`sf::st_join`).
* **Source:** Statistics Canada, 2021 Census Boundary files.
* **Download URL:** [https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/ldb_000b21a_e.zip](https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/ldb_000b21a_e.zip)
* **Local Path (Git-ignored):** Extract to `.scratch/shp/`

### C. Statistics Canada Geographic Attribute File (GAF)
* **Format Required:** CSV
* **Purpose:** A master crosswalk table linking every Dissemination Block (DBUID) to its full higher-geography hierarchy (Dissemination Areas, Census Tracts, Health Regions, etc.).
* **Source:** Statistics Canada, Catalogue 92-151-X.
* **Download URL:** [https://www12.statcan.gc.ca/census-recensement/2021/geo/aip-pia/attribute-attribs/files-fichiers/2021_92-151_X.zip](https://www12.statcan.gc.ca/census-recensement/2021/geo/aip-pia/attribute-attribs/files-fichiers/2021_92-151_X.zip)
* **Local Path (Git-ignored):** Extract to `.scratch/gaf/`

*(Note: The National Address Register and GeoNames postal centroids datasets are generated earlier in the pipeline by `m1_build_centroids.R`. The latest published full centroid artifact is in `releases/m1/2026-06-26-nar-geonames-centroids/` with its manifest.)*

## 2. Execution

With the raw `.shp` and `.csv` datasets placed in the local `.scratch/` directories (which are git-ignored due to their massive size >700MB), you can execute the pipeline:

1. **Centroid Generation:** Run `scripts/m1_build_centroids.R` (generates `ontario_postal_centroids.csv`).
2. **DB Assignment & GAF Rollup:** Run `scripts/m1_gaf_rollup.R`.

### What `m1_gaf_rollup.R` does:
1. Loads the pinned province and DB boundary files and filters both to Ontario
   (`PRUID == 35`).
2. Converts the raw postal centroids to `sf` spatial points and aligns each
   input CRS.
3. Rejects points outside the independent Ontario polygon and rejects points
   intersecting multiple DBs.
4. Assigns exactly one `DBUID` where possible. Points inside Ontario with no
   2021 DB intersection remain explicit as
   `unmatched_no_2021_ontario_db`; matched points use
   `matched_2021_ontario_db`.
5. Executes a flat `left_join` against the GAF and requires every matched DB
   to have a `DAUID`.

## 3. Deliverables

The final output is the `ontario_postal_gaf_rollup.csv` dataset, which contains the complete correspondence mapping. Due to GitHub's file size limits (the raw CSV is ~250MB), the tracked deliverable in the repository is compressed via `gzip` and stored locally in the `handoff/` directory.
