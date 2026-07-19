______________________________________________________________________

## description: Produce final release-readiness assessment for lint, tests, CI consistency, docs sync, and dependency hygiene.

Prepare a release-readiness report for the current branch.

Release target:

- {{RELEASE_TAG_OR_BRANCH}}

Checklist:

1. Strict lint status.
1. Full test suite status.
1. Coverage expectation status.
1. CI workflow consistency and dependency update posture.
1. Documentation sync across README, Instructions.md, and docs/.
1. Release notes/description presence and quality.

Required output:

1. Ready or Not Ready decision.
1. Blocking issues with file-level references.
1. Recommended final actions before merge/release.
