______________________________________________________________________

## name: ci-lint-hardening description: "Use when updating lint tooling, workflow checks, or CI reliability policies for shell, YAML, Dockerfile, and markdown validation."

# CI Lint Hardening

## Goal

Keep CI strict, reproducible, and suppression-free.

## Procedure

1. Align workflow checks with `tests/lint.sh` strict mode.
1. Ensure required tools are installed in CI lint job.
1. Validate actionlint, yamllint, shellcheck, shfmt, hadolint, and mdformat flow.
1. Confirm line-length policy: 140 for shell/YAML/Docker only.
1. Confirm markdown linting remains mandatory without markdown max-line checks.

## Guardrails

1. No rule disable/ignore additions.
1. Keep workflow shell quoting robust.
1. Keep action versions on stable final releases.

## Output

1. Updated workflow/config files.
1. Exact commands used for local parity checks.
1. Any residual risks or environment caveats.
