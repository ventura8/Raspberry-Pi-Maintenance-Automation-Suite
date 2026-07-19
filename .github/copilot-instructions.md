# Copilot Instructions

## Project Context

This project automates maintenance operations for Raspberry Pi and Linux systems using Bash scripts, with BATS-based tests and Dockerized CI.

## Engineering Expectations

1. Prefer simple, explicit Bash over clever one-liners.
1. Keep script behavior deterministic and testable under mocks.
1. Maintain compatibility with both Raspberry Pi and non-Pi Linux paths where intended.
1. Keep email/reporting and reboot signaling behavior stable unless explicitly changing requirements.

## Quality Gates

1. No lint/formatter suppressions, no disable directives, and no broad ignores.
1. Enforce formatting and lint policies via existing tooling in `tests/lint.sh` and `tests/format.sh`.
1. Respect line-length standards:

- 140 max for shell, YAML, and Dockerfiles.
- No markdown max-line enforcement.

4. Complexity gates must be satisfied by improving control flow and structure, never by deleting useful comments.

## Testing and CI

1. Update or add BATS tests with any behavior changes.
1. Keep CI workflow steps shell-safe and quote variables in command invocations.
1. Ensure changes pass strict lint and project suite before finalizing.

## Documentation Discipline

When behavior or standards change, update:

1. `README.md` for user-facing expectations.
1. `Instructions.md` for project AI/developer guidance.
1. `docs/development_standards.md` for policy-level requirements.
