______________________________________________________________________

## name: triage-issue-and-scope description: "Use when a bug report, regression, or feature request needs fast impact analysis across scripts, tests, CI, and docs in this repository."

# Triage Issue and Scope

## Goal

Produce a concrete change scope before implementation.

## Inputs

1. User request or bug details.
1. Suspected scripts or workflows.

## Procedure

1. Identify affected runtime path: Pi-only, non-Pi, or both.
1. Map impacted files in `scripts/`, `install.sh`, and `tests/`.
1. Check whether lint/CI policy updates are needed.
1. Define acceptance criteria with explicit pass/fail signals.

## Output

1. Minimal file list to change.
1. Required tests to add/update.
1. Validation command sequence.
