# OPCC Release and Deprecation Policy

## Release requirements

An OPCC release is a new immutable vintage. Before publication, maintainers
must confirm source provenance and licences, manifests and checksums, schema and
semantic invariants, package tests, and the release notes. External M6
maintenance provides a separate producing rebuild, verification rebuild, drift
report, and a human publication gate; it never publishes automatically.

The published record includes the release identifier, source vintage, code
revision, checksums, attribution, and a concise change summary. GitHub Releases
are OPCC's durable public distribution channel. A release is not overwritten.
If an artifact must be replaced, publish a superseding vintage and explain the
relationship in the release index and notes. OPCC does not currently maintain a
Zenodo/DOI mirror.

## Corrections and withdrawals

Corrections require open, reproducible evidence and both technical and
provenance/licence review. Maintainers preserve the prior release when lawful,
mark it as superseded or withdrawn where appropriate, and publish a new
versioned artifact. Restricted or privacy-sensitive material is never retained
just to preserve history.

## Compatibility and deprecation

Breaking API or schema changes are announced in `NEWS.md`, documented in the
release notes, and retain a migration note for at least one subsequent release
when practical. Deprecated behavior remains documented until removal. The
package version and release vintage are distinct: package versions describe API
behavior, while artifact vintages identify evidence and source state.
