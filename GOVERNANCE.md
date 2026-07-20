# OPCC Governance

## Roles

- **Contributors** propose open evidence, documentation, tests, or fixes.
- **Reviewers** assess technical validity or provenance and licence compliance.
- **Maintainers** merge changes, publish releases, manage project access, and
  keep the project reproducible.

Maintainers are added or removed by a documented maintainer decision in a
public issue or pull request. At least one active maintainer must be able to
perform a release using only the public documentation. If the project becomes
unmaintained, its existing immutable releases and documentation remain public;
new ownership must be established through a documented public decision.

## Decisions

Routine fixes are decided by one maintainer. Data, release, policy, security,
or compatibility decisions need a written rationale and, where applicable, the
two reviews described in [CONTRIBUTING.md](CONTRIBUTING.md). Significant or
contested decisions are recorded as dated files in `docs/decisions/` with the
context, decision, rationale, and reopening condition.

## Disputes and appeals

Raise a concern in the relevant issue unless it involves conduct or security.
A maintainer not materially involved in the original decision reviews the
evidence. The outcome and rationale are recorded publicly when safe to do so.

## Releases and corrections

Only maintainers publish releases. Releases are immutable; corrections and
withdrawals create a new superseding vintage with a visible rationale. See the
[release policy](docs/release-policy.md).

