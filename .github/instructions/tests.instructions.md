______________________________________________________________________

## applyTo: "tests/\*\*/\*.{bats,sh}" description: "Use when modifying BATS tests or test harness scripts; enforces deterministic tests, mock hygiene, and coverage discipline."

# Test Instructions

## Test Design

1. Keep tests deterministic and independent.
1. Prefer validating observable behavior over implementation details.
1. Ensure each new behavior change has matching tests.

## Mocks and Fixtures

1. Reuse existing mock setup patterns from `tests/setup_mocks.sh`.
1. Preserve compatibility for Linux CI and Windows-hosted local runs.
1. Keep mock behavior minimal but realistic for branch conditions.

## Coverage and Validation

1. Maintain project expectation of >= 90% coverage.
1. Run targeted tests first, then the full suite.
1. Keep test output clear enough to diagnose regressions quickly.
