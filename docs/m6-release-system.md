# M6 Release Controls

M6 adds automated controls around immutable OPCC releases. It never modifies a
published vintage. A corrected or rebuilt result is a new candidate and, after
review, a superseding release.

## Current control plane

Run `Rscript scripts/m6_release_controls.R` from the repository root. The
audit verifies that every indexed M2 and M5 artifact and manifest exists,
matches its SHA-256 checksum, and is referenced by a commit-pinned GitHub raw
URL. A mutable branch URL is rejected.

`release_drift_report()` compares a prior and candidate table using explicit
key columns. It reports added, removed, and allocation-weight-changed keys and
postal-code coverage changes. Candidate publication must attach this report to
the release run brief.

## Remaining M6 gates

The next controls are a scheduled NAR metadata watch, a locked dependency and
build-environment record, and an isolated clean-room rebuild/verification job.
The clean-room job remains blocked until the immutable public endpoint is
intentionally available to an unauthenticated runner. No automation publishes
a release: opening a release branch and issue remains review-only, and a human
publish approval is required.
