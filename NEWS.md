# OPCC 0.0.1

- Every use of a suggested package is now conditional. `dplyr` was used
  unguarded throughout the source-layer validation path, and `rlang` was
  missing from the build dependency check, so a missing package surfaced as
  an obscure namespace error instead of a list of packages to install.
- `run_app()` no longer uses `rlang` to report which Shiny packages are
  missing, since `rlang` is itself only suggested. It also enforces the
  `bslib >= 0.6.0` floor that `DESCRIPTION` now declares.
- Release and build downloads fail with an actionable message when the remote
  resource is unavailable, instead of surfacing a raw connection error.
- `sli_make_synthetic_qa()` restores the caller's random-number stream rather
  than leaving it reseeded.
- Added `export_postal_points()`, which writes the postal-code point
  shapefile for a join. The reproducer script the Shiny app generates now
  calls it instead of reaching into unexported internals, so the script a user
  is handed runs entirely on public API.
- The optional Public Health Unit overlay is now read only from the user's own
  app cache. OPCC no longer obtains the boundary file from another package,
  and the map simply omits the overlay when no cached file is present.
- Added an `opcc_postal_points.zip` download to the Shiny app that exports
  the user's postal codes as a zipped ESRI point shapefile.
- Initial public release with checksum-verified postal-code-to-DB and
  postal-code-to-DA correspondence lookups.
- Added source-separated local evidence layers and contribution bundles.
- Added an inclusive broad Ontario coordinate guardrail with distinct
  quarantine reasons and validation-report counts.
- Added exact Ontario-boundary and 2021 DB assignment safeguards for canonical
  point candidates, including explicit matched and unmatched statuses.
- Added an aggregate-only, many-to-many DB/DA validation engine for
  maintainer-held licensed benchmarks, with fail-closed private output paths.
- Added a private PCCF runner that checksum-binds M1, M2, and M5, rejects
  incompatible M5-to-M2 ancestry, validates an explicit Ontario PCCF contract,
  and writes aggregate-only outputs outside the repository.
- Added a DA-only XLSX validation path for PCCF-derived exports that lack
  coordinates and DBUIDs, with explicit M1/M2 non-validation and vintage-gap
  reporting.
- Published a disclosure-minimised M5 external-reference attestation and
  validation summary, including agreement, coverage, provenance, and scope
  limitations.
- Added immutable release-index validation and release-control auditing.
- Added a Shiny app (`run_app()`) that joins an uploaded CSV or typed
  semicolon-separated postal codes to the postal-code-to-DA correspondence,
  draws the matched dissemination areas on a map, and downloads the joined
  CSV, the map as HTML, and a reproducer script; added
  `download_da_boundaries()` for the cached 2021 StatCan DA boundary files.
- Reworked the Shiny app around one shared control panel for both outputs:
  base-map tile choice, a locally cached simplified Public Health Unit
  boundary overlay, postal-code points from the checksum-verified M1 centroid
  artifact (cached after one ~6 MB download), and a colored join summary.
  The Ontario DA plot layer is simplified once and reused from the local
  cache; the ~200 MB StatCan boundary file is downloaded only on first use.
