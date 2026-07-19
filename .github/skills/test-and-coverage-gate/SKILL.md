______________________________________________________________________

## name: test-and-coverage-gate description: "Use when validating repository changes with BATS, coverage generation, and strict quality gate checks before merge."

# Test and Coverage Gate

## Goal

Ensure code changes are test-complete and coverage-compliant.

## Procedure

1. Run focused tests for changed behavior first.
1. Run full suite and capture failures precisely.
1. If coverage mode is requested, generate and verify reports.
1. Confirm coverage target remains >= 90%.

## Standard Commands

1. `./tests/run_suite.sh`
1. `COVERAGE=1 ./tests/run_suite.sh`
1. `powershell -ExecutionPolicy Bypass -File .\\tools\\windows\\run_tests_local.ps1 -NoCoverage` for Windows-hosted local runs.

## Output

1. Pass/fail status by test area.
1. Any missing test cases for changed logic.
1. Coverage summary against target.
