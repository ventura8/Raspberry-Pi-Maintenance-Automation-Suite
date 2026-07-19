______________________________________________________________________

## applyTo: "\*\*/\*.{yml,yaml}" description: "Use when editing workflow or YAML config files; enforces CI reliability, strict lint compatibility, and quoting correctness."

# CI and YAML Instructions

## Workflow Reliability

1. Keep workflow steps deterministic and idempotent.
1. Pin to stable action versions.
1. Avoid unnecessary permission expansion in workflow jobs.

## Shell-in-YAML Safety

1. Quote interpolated paths and variables in shell commands.
1. Keep multi-line run blocks readable and lint-clean.
1. Ensure Docker command arguments remain explicit and portable.

## Policy Constraints

1. Keep YAML lint-compliant with max line length 140.
1. Do not disable actionlint/yamllint checks.
1. Keep CI behavior aligned with `tests/lint.sh` and test wrappers.
