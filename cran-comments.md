## Test environments

- Ubuntu 24.04.4 LTS (x86_64-pc-linux-gnu), R 4.6.1: fresh source-archive
  build and full `R CMD check --as-cran` against the built tarball,
  including rendered vignette, PDF manual, and HTML manual. `pandoc`,
  `pdflatex`, and `qpdf` were available.
- The same tarball rechecked with `_R_CHECK_DEPENDS_ONLY_=true`, so only
  Depends and Imports were visible, to confirm every use of a suggested
  package is conditional.

## R CMD check results

Checks were run on 2026-08-21 against OPCC `main` at
`5b8af9a68750c1749d56df26c75baefec7087377`.

- `R CMD build OPCC` with vignettes: OK.
- `R CMD check --as-cran OPCC_0.0.1.tar.gz`: `Status: 1 NOTE`.
- The sole NOTE is CRAN incoming feasibility identifying this as a new
  submission; there are no package ERRORs or WARNINGs.
- Package test suite under check: 456 passing, 13 skipped, 0 failures. The
  skips are tests that need a source checkout, a build script that is not
  installed with the runtime package, a cached artifact, or that are
  deliberately `skip_on_cran()`.
- `R CMD check --as-cran` with `_R_CHECK_DEPENDS_ONLY_=true`:
  `Status: 1 NOTE`, the same new-submission NOTE; 377 passing, 30 skipped,
  0 failures.
- `urlchecker::url_check()`: all checked URLs are correct.
- `spelling::spell_check_package()`: no spelling errors. Package-specific
  technical terms are recorded in `inst/WORDLIST`.

## Submission notes

- OPCC uses only publicly redistributable source-qualified evidence.
- Remote artifact downloads are checksum-verified and use commit-pinned URLs.
- This is a new submission with no downstream dependencies.

## Not yet re-run at this commit

The following were last run on 2026-08-05 against `51e026a7a5ce96abd720c62a17b2ab862c93b4ec`,
which predates the current Shiny app, the point-shapefile download, and the
conditional-Suggests fix. They should be repeated before submission:

- macOS `R CMD check --as-cran`.
- GitHub Actions cross-platform check (Ubuntu, macOS, Windows) plus Ubuntu
  release validation; run 30308582050 passed at that earlier commit.
