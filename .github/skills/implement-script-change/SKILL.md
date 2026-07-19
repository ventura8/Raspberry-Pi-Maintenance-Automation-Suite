______________________________________________________________________

## name: implement-script-change description: "Use when adding or modifying Bash behavior in install.sh or scripts/\* while preserving safety, portability, and existing update flows."

# Implement Script Change

## Goal

Apply Bash behavior changes safely with minimal regressions.

## Procedure

1. Keep modifications localized and avoid broad rewrites.
1. Preserve non-interactive and cron-safe execution paths.
1. Prefer explicit branching and readable helper functions.
1. Ensure new behavior is reflected in matching BATS tests.
1. Re-run lint and targeted tests before full suite.

## Guardrails

1. No shellcheck suppression comments.
1. Keep shell line length \<= 140.
1. Do not introduce interactive prompts into automated paths.

## Validation

1. `STRICT_MODE=true ./tests/lint.sh`
1. `./tests/run_suite.sh --test-file <relevant test>` where possible
1. `./tests/run_suite.sh`
