## Test environments

- Ubuntu 24.04.4 LTS (x86_64-pc-linux-gnu), R 4.6.1: fresh source-archive
  build and full `R CMD check --as-cran` against the built tarball,
  including rendered vignette, PDF manual, and HTML manual. `pandoc`,
  `pdflatex`, and `qpdf` were available.
- The same tarball rechecked with `_R_CHECK_DEPENDS_ONLY_=true`, so only
  Depends and Imports were visible, to confirm every use of a suggested
  package is conditional.

## R CMD check results

Checks were run on 2026-08-24 against OPCC 0.0.1.

- `R CMD build OPCC` with vignettes: OK.
- `R CMD check --as-cran OPCC_0.0.1.tar.gz`: `Status: 1 NOTE`.
- The sole NOTE is CRAN incoming feasibility identifying this as a new
  submission; there are no package ERRORs or WARNINGs.
- Package test suite under check: 454 passing, 13 skipped, 0 failures. The
  skips are tests that need a source checkout, a build script that is not
  installed with the runtime package, a cached artifact, or that are
  deliberately `skip_on_cran()`.
- `R CMD check --as-cran` with `_R_CHECK_DEPENDS_ONLY_=true`:
  `Status: 1 NOTE`, the same new-submission NOTE; 375 passing, 30 skipped,
  0 failures.
- With all suggested packages installed, the full suite runs 519 passing,
  0 skipped, 0 failures.
- `urlchecker::url_check()`: all checked URLs are correct.
- `spelling::spell_check_package()`: no spelling errors. Package-specific
  technical terms are recorded in `inst/WORDLIST`.

## Submission notes

- OPCC uses only publicly redistributable source-qualified evidence.
- Remote artifact downloads are checksum-verified and use commit-pinned URLs.
  Download failures are reported with an actionable message rather than a raw
  connection error.
- Every use of a suggested package is guarded. The guards are exercised by the
  `_R_CHECK_DEPENDS_ONLY_=true` run above, where the affected tests skip
  explicitly rather than relying on testthat's automatic skip.
- Examples that would fetch a release artifact are wrapped in `\donttest{}`
  with an inner `if (interactive())` guard, so no example downloads anything
  during `R CMD check --as-cran`.
- This is a new submission with no downstream dependencies.

## Not yet re-run on this package surface

- Cross-platform GitHub Actions checks (Ubuntu, macOS, Windows) plus Ubuntu
  release validation. Run 32545802566 passed all four jobs, but it describes
  an earlier commit and predates the changes checked above. It must be re-run
  once these changes are pushed.
- macOS `R CMD check --as-cran` outside GitHub Actions.
