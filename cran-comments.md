## R CMD check results

Local checks were run on 2026-07-23 with R 4.6.1 on Ubuntu 24.04.

- `R CMD build OPCC` with vignettes: OK.
- `R CMD check OPCC_0.0.1.tar.gz --no-manual`: OK.
- Local `R CMD check --as-cran` with remote incoming and system-clock checks
  disabled: OK apart from the maintainer/package notes listed below.
- Full `devtools::test()`: passed; four tests skip only because they require
  network access in this offline environment.
- GitHub Actions: pending cross-platform checks.

The local `--as-cran` run cannot complete CRAN/Bioconductor incoming-network
lookups on this host. A networked clean-host `--as-cran` run remains required
before submission.

The repository-only governance, research, and build-script paths are excluded
from the CRAN source tarball with `.Rbuildignore`. The package manual usage
signatures are wrapped to avoid line-width notes.

## Submission notes

- OPCC uses only publicly redistributable source-qualified evidence.
- Remote artifact downloads are checksum-verified and use commit-pinned URLs.
