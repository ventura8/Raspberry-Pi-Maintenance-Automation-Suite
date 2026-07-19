______________________________________________________________________

## name: release-readiness description: "Use when preparing a final merge or release candidate by verifying lint, tests, CI consistency, docs sync, and dependency hygiene."

# Release Readiness

## Goal

Produce a clean pre-merge or pre-release state.

## Checklist

1. Strict lint passes.
1. Full test suite passes.
1. Coverage target maintained.
1. CI workflow and Docker test image remain buildable.
1. Docs reflect current behavior and policy.
1. Dependency update configs (including Dependabot) are in sync.

## Output

1. Readiness status: pass/fail.
1. Blocking issues with file-level pointers.
1. Short remediation list for any blockers.
