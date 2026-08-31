# OPCC 1.0.0

- First CRAN release.
- The Shiny app can now reuse the simplified dissemination-area boundary
  artifact between sessions, so a lookup draws its map in about a second
  instead of re-downloading the Statistics Canada boundary file and
  re-simplifying every Ontario dissemination area on each launch. The cache is
  never created without permission: point `OPCC.shiny_da_cache_dir` or
  `OPCC_SHINY_DA_CACHE_DIR` at a directory, or answer the one-time prompt shown
  in an interactive session. The answer is remembered, and with no setting and
  no recorded answer the app keeps everything in a session-only temporary
  directory.
- Typed postal codes are now checked against the Canadian `A1A 1A1` format
  before the join runs. Malformed entries are listed back by name and skipped,
  and the join continues with the valid ones instead of silently reporting
  them as invalid afterwards.
- The Shiny app header shows the installed package version beside the title,
  and the download buttons now follow the app's teal palette.
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
