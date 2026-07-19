______________________________________________________________________

## description: Harden CI lint and formatting gates for shell, YAML, Dockerfile, and markdown policy compliance.

Review and improve CI lint reliability for this repository.

Task input:

- {{CI_OR_LINT_GOAL}}

Required checks:

1. Ensure strict parity with tests/lint.sh policy.
1. Validate shellcheck, shfmt, bash -n, yamllint, actionlint, hadolint, and markdown checks.
1. Enforce 140-char limits for shell/YAML/Docker only.
1. Keep markdown lint mandatory with no markdown max line-length enforcement.
1. Ensure no lint suppressions/disables/ignores are introduced.

Deliverables:

1. Exact files changed.
1. Why each change was needed.
1. Local commands to reproduce lint validation.
1. Remaining CI risks, if any.
