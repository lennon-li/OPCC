## Test environments

- Ubuntu 24.04.4 LTS (x86_64-pc-linux-gnu), R 4.6.1: fresh source-archive
  build and full `R CMD check --as-cran` against the built tarball,
  including rendered vignette, PDF manual, and HTML manual. `pandoc`,
  `pdflatex`, and `qpdf` were available.
- The same tarball rechecked with `_R_CHECK_DEPENDS_ONLY_=true`, so only
  Depends and Imports were visible, to confirm every use of a suggested
  package is conditional. That run adds `--no-build-vignettes`, because
  re-building the vignette needs `rmarkdown`, which is a suggested package
  and therefore deliberately absent from that library.

## R CMD check results

Checks were run on 2026-08-30 against OPCC 0.0.1.

- `R CMD build OPCC` with vignettes: OK.
- `R CMD check --as-cran OPCC_0.0.1.tar.gz`: `Status: 1 NOTE`.
- The sole NOTE is CRAN incoming feasibility identifying this as a new
  submission; there are no package ERRORs or WARNINGs.
- Package test suite under check: 530 passing, 10 skipped, 0 failures. The
  skips are tests that need a source checkout, a build script that is not
  installed with the runtime package, a cached artifact, or the opt-in
  installed-app browser test.
- `R CMD check --as-cran` with `_R_CHECK_DEPENDS_ONLY_=true`:
  `Status: 1 NOTE`, the same new-submission NOTE; 414 passing, 38 skipped,
  0 failures.
- With all suggested packages installed, the full local suite runs 587
  passing, 1 skip (the opt-in browser test), and 0 failures.
- `urlchecker::url_check()`: all checked URLs are correct.
- `spelling::spell_check_package()`: no spelling errors. Package-specific
  technical terms are recorded in `inst/WORDLIST`.

## Submission notes

- OPCC uses only publicly redistributable source-qualified evidence.
- Remote artifact downloads are checksum-verified and use commit-pinned URLs.
  Download failures are reported with an actionable message rather than a raw
  connection error, and large downloads raise the `timeout` option for the
  duration of the transfer, restoring the user's value afterwards.
- Every use of a suggested package is guarded. The guards are exercised by the
  `_R_CHECK_DEPENDS_ONLY_=true` run above, where the affected tests skip
  explicitly rather than relying on testthat's automatic skip. This includes
  `testthat::skip_if_offline()`, which itself requires `curl`; the tests reach
  it through a helper that checks for `curl` first, so it skips rather than
  errors when Suggests are unavailable.
- Examples that would fetch a release artifact are wrapped in `\donttest{}`
  with an inner `if (interactive())` guard, so no example downloads anything
  during `R CMD check --as-cran`.
- This is a new submission with no downstream dependencies.

## Not yet re-run on the current package surface

- Cross-platform GitHub Actions results. The last green run
  (`32789251230`, commit `e18f6c1`) checked ubuntu-latest, macos-latest, and
  windows-latest with `rcmdcheck::rcmdcheck(args = c("--no-manual",
  "--as-cran"))` plus an Ubuntu release-validation job, all with 0 errors,
  0 warnings, and the new-submission NOTE. It predates the current
  documentation and test-guard changes, which have not yet been pushed.
- macOS `R CMD check --as-cran` outside GitHub Actions, including the PDF
  manual, which the CI package-check jobs skip via `--no-manual`.
- The opt-in installed-app browser test (`OPCC_RUN_BROWSER_TESTS=true`). It
  last passed on 2026-08-24 at commit `e18f6c1`. It cannot currently be run on
  the maintainer's machine because of an unrelated instability between
  `chromote` and the locally installed Chrome; no package code has changed
  since that run.
