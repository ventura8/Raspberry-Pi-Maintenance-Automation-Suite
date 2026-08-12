______________________________________________________________________

## name: test-and-coverage-gate description: Run BATS with coverage and complexity gates; report overall/per-file thresholds and badge status.

# Test and Coverage Gate

## Goal

Prove the suite meets coverage ≥90% and complexity ≤15 (overall and per-file).

## Procedure

1. Prefer Docker coverage gate: `./scripts/build-and-test.sh --coverage-only`
1. Host fallback: `COVERAGE=1 ./tests/run_suite.sh`
1. Confirm `tests/transform_coverage.py` thresholds.
1. Commit `assets/coverage.svg` when coverage changes.
1. For installer-only or maintenance-only iteration, use `./tests/run_suite.sh --installer-only` /
   `--maintenance-only`, then re-run full coverage before merge claims.

## Companion skill

See [`.agents/skills/test-runner/SKILL.md`](../../../.agents/skills/test-runner/SKILL.md).

## Output

Coverage %, complexity, failing files/tests, badge updated yes/no.
