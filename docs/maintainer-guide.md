# OPCC Maintainer Guide

This guide is intentionally public: a new maintainer must be able to review a
contribution and verify a release without private runbooks or data.

## Review a contribution

1. Confirm the proposal uses only open, redistributable evidence and has a
   stable endpoint, licence, attribution, retrieval date, lineage, adapter
   configuration, fixture, and quality report.
2. Run the package tests and any source-specific validation described by the
   proposed adapter.
3. Record separate technical and provenance/licence approvals in the issue or
   pull request. Do not merge a data change without both.
4. Ensure the release is a new vintage: never alter a published artifact in
   place.

## Verify and publish a release

1. Start from the tagged code revision and public source manifests.
2. Build the candidate and run the documented release validator and package
   checks.
3. Review the independent M6 maintenance report, including the separate
   verification build and any source/schema/hash drift. A human maintainer must
   make the publication decision.
4. Publish the immutable artifact, manifest, checksums, source attribution,
   and release notes. Update `NEWS.md` for user-visible package changes.
5. If a correction is required, publish a superseding vintage under
   [the release policy](release-policy.md); do not overwrite history.

## Maintainership and incidents

Record maintainer additions/removals and material decisions as described in
[GOVERNANCE.md](../GOVERNANCE.md). Route conduct reports under the Code of
Conduct and vulnerabilities under the Security Policy; do not place private or
restricted content in public issues.

