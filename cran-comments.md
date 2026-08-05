## Test environments

- macOS Tahoe 26.5.2 (arm64), R 4.6.1: fresh source-archive build and full
  `R CMD check --as-cran`, including rendered vignette, PDF manual, and HTML
  manual. The run used Quarto's bundled Pandoc through an audit-local shim;
  `pdflatex` and Homebrew Tidy were available.
- GitHub Actions run 30308582050: Ubuntu, macOS, and Windows package checks,
  plus Ubuntu release validation, all passed.

## R CMD check results

Checks were rerun on 2026-07-29 against the current source snapshot based on
OPCC `main` at `48d928e09f7c40315fd892e234ff484cfde2d4af`, including the
vignette removal of the invalid placeholder endpoint.

- `R CMD build OPCC` with vignettes: OK.
- `R CMD check --as-cran OPCC_0.0.1.tar.gz`: OK; `Status: 1 NOTE` only.
- The sole NOTE is CRAN incoming feasibility identifying this as a new
  submission; there are no package ERRORs or WARNINGs.
- The current-checkout test suite passed.
- `urlchecker::url_check()`: all checked URLs are correct.
- `spelling::spell_check_package()`: no spelling errors. Package-specific
  technical terms are recorded in `inst/WORDLIST`.

## Submission notes

- OPCC uses only publicly redistributable source-qualified evidence.
- Remote artifact downloads are checksum-verified and use commit-pinned URLs.
- This is a new submission with no downstream dependencies.
