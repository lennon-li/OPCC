## Test environments

- Ubuntu 24.04.4 LTS (x86_64-pc-linux-gnu), R 4.6.1: fresh source-archive
  build and full `R CMD check --as-cran` against the built tarball,
  including rendered vignette, PDF manual, and HTML manual. `pandoc` 3.1.3,
  `pdflatex` (TeX Live 2026), and `qpdf` 11.9.0 were available.
- The same tarball rechecked with `_R_CHECK_DEPENDS_ONLY_=true`, so only
  Depends and Imports were visible, to confirm every use of a suggested
  package is conditional. That run also builds and re-builds the vignette,
  because `R CMD check` makes the `VignetteBuilder` package available even
  when only Depends and Imports are otherwise visible.
- GitHub Actions on ubuntu-latest, macos-latest, and windows-latest with
  R release, plus a separate ubuntu-latest job on R-devel. All four run
  `rcmdcheck::rcmdcheck(args = c("--no-manual", "--as-cran"),
  error_on = "warning")`.

## R CMD check results

Checks were run on 2026-08-31 against OPCC 1.0.0.

- `R CMD build OPCC` with vignettes: OK.
- `R CMD check --as-cran OPCC_1.0.0.tar.gz`: `Status: 1 NOTE`.
- The sole NOTE is CRAN incoming feasibility identifying this as a new
  submission; there are no package ERRORs or WARNINGs.
- Package test suite under check: 537 passing, 14 skipped, 0 failures. The
  skips are tests that need a source checkout, a build script that is not
  installed with the runtime package, a locally cached artifact, or the
  opt-in installed-app browser test. Every skip reports its own reason; the
  cached-artifact skips mean the exact pass/skip split varies with what is
  cached on the checking machine.
- `R CMD check --as-cran` with `_R_CHECK_DEPENDS_ONLY_=true`:
  `Status: 1 NOTE`, the same new-submission NOTE; 423 passing, 40 skipped,
  0 failures.
- With all suggested packages installed, the full local suite runs 602
  passing, 1 skip (the opt-in browser test), and 0 failures.
- All four GitHub Actions check jobs passed on the exact commit submitted
  here. Because they run with `error_on = "warning"`, a passing job is
  itself evidence of 0 errors and 0 warnings on that platform. A fifth job
  re-validates the released data artifacts.
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
- The package writes nothing to the user's home filespace without permission.
  The Shiny app can reuse a simplified boundary artifact between sessions, but
  that cache is used only when the user points `OPCC.shiny_da_cache_dir` (or
  `OPCC_SHINY_DA_CACHE_DIR`) at a directory, or answers a one-time interactive
  console prompt. With no setting and no recorded answer the app keeps
  everything in a session-only `tempdir()` location and removes it when the
  session ends. The prompt is reached only from `interactive()` sessions, so
  `R CMD check` never prompts and never creates the cache or the file that
  records the answer.
- This is a new submission with no downstream dependencies.

## Not yet re-run on the current package surface

- macOS and Windows `R CMD check --as-cran` including the PDF manual. The
  GitHub Actions jobs on those platforms pass `--no-manual`; the PDF manual
  is built and checked only in the Linux run above.
- The opt-in installed-app browser test (`OPCC_RUN_BROWSER_TESTS=true`). It
  last passed on 2026-08-24. The Shiny application has changed since then, so
  this end-to-end check is currently unverified; the affected behaviour is
  covered by non-browser `shiny::testServer()` tests that do run. It cannot
  currently be run on the maintainer's machine because of an unrelated
  instability between `chromote` and the locally installed Chrome. The test
  never runs during `R CMD check`.
