# Agent Guide: Raspberry Pi Maintenance Automation Suite

This repository is shell-first and quality-gated by lint + BATS tests. Agents should optimize for safe Bash changes, deterministic tests, and CI parity.

## Core Rules

1. Keep changes minimal and scoped to the requested behavior.
1. Do not add lint suppressions, disables, or ignore directives for linters/formatters.
1. Preserve line-length policy: 140 for shell, YAML, and Dockerfiles. Markdown has no max-line constraint.
1. Prefer portable Bash patterns that work in Linux CI and local Docker-based test runs.
1. Avoid destructive operations unless explicitly requested.
1. Do not reduce complexity metrics by removing useful comments; reduce complexity through logic refactoring only.

## Required Local Validation After Code Changes

Run these in order:

1. `./tests/format.sh`
1. `STRICT_MODE=true ./tests/lint.sh`
1. `./tests/run_suite.sh`

When running on Windows host, use project wrappers when needed:

- `powershell -ExecutionPolicy Bypass -File .\tools\windows\run_tests_local.ps1 -NoCoverage`

## Project-Specific Implementation Notes

1. `install.sh` supports interactive mode and non-interactive update mode (`--update`).
1. Non-Pi paths must continue to allow firmware updates while skipping Pi-only tasks.
1. `scripts/update_self.sh` must remain cron-safe and avoid stdin-pipe assumptions.
1. Samsung firmware flow prefers `fwupdmgr` and falls back to page scraping/extraction.

## Files That Usually Need Coordinated Updates

1. Script logic: `scripts/*.sh` and `install.sh`
1. Tests: `tests/*.bats`, `tests/run_suite.sh`, `tests/setup_mocks.sh`
1. CI/lint: `.github/workflows/ci.yml`, `tests/lint.sh`, config files in repo root
1. Docs: `README.md`, `Instructions.md`, `docs/*.md`

## PR Readiness Checklist

1. Lint passes in strict mode.
1. Relevant BATS tests added or updated.
1. Coverage expectations preserved (target >= 90%).
1. CI workflow changes validated for quoting and shell safety.
1. Documentation updated when behavior/policy changed.
