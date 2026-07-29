## Test environments

- macOS Tahoe 26.5.2 (arm64), R 4.6.1: fresh source-tree build and full
  `R CMD check --as-cran`, including rendered vignette, PDF manual, and HTML
  manual.
- GitHub Actions run 30308582050: Ubuntu, macOS, and Windows package checks,
  plus Ubuntu release validation, all passed.

## R CMD check results

Checks were run on 2026-07-29 against OPCC `main` at
`f756da475bef59c5ecec3d64f5d28a42599c8b0f`.

- `R CMD build OPCC` with vignettes: OK.
- `R CMD check --as-cran OPCC_0.0.1.tar.gz`: OK; `Status: 1 NOTE` only.
- The sole NOTE is CRAN incoming feasibility identifying this as a new
  submission; there are no package ERRORs or WARNINGs.
- `spelling::spell_check_package()`: no spelling errors.
- `urlchecker::url_check()`: all checked URLs are correct.
- The built tarball was inspected; repository-only governance, research, build,
  and release-artifact paths are excluded through `.Rbuildignore`.

## Submission notes

- OPCC uses only publicly redistributable source-qualified evidence.
- Remote artifact downloads are checksum-verified and use commit-pinned URLs.
- This is a new submission with no downstream dependencies.
