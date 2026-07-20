# Contributing to OPCC

Thanks for helping improve an open, reproducible Ontario postal-code
correspondence. OPCC accepts only evidence that can be publicly redistributed,
reviewed, and reproduced.

## Before opening an issue or pull request

1. Read the [source-adapter guide](docs/m4-contributing-source.md) and the
   [release policy](docs/release-policy.md).
2. Never submit Canada Post, PCCF, PCCF+, credentials, personal addresses, or
   other restricted data. Do not use an issue as a way to disclose private
   information.
3. For a new source, run `contribution_bundle()` locally and attach the bundle
   manually to a **Source proposal** issue. The function creates a prefilled
   issue URL; it does not upload data.
4. For an error in a published release, use the **Data correction** issue
   template and give open, reproducible evidence.

## Pull requests

Keep each pull request focused. Include the source licence, stable endpoint,
retrieval date, lineage, schema mapping, a small redistributable fixture, and
the coverage or regression effect. Run the checks that apply to your change.
For package changes, run `Rscript -e 'testthat::test_dir("tests/testthat")'`.

Data changes need two distinct maintainer approvals:

1. technical validation (schema, fixtures, tests, and regression impact); and
2. provenance and licence review (redistributability, lineage, attribution,
   and restricted-source exclusion).

Maintainers may request changes, reject evidence that cannot be redistributed,
or publish an accepted correction only as a new immutable vintage.

## Decisions and conduct

Participation follows the [Code of Conduct](CODE_OF_CONDUCT.md). Material
source, release, policy, or compatibility decisions are recorded in the pull
request, issue, or a dated decision record under `docs/decisions/`. See
[governance](GOVERNANCE.md) for how maintainers make and appeal decisions.

