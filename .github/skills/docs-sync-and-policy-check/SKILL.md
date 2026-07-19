______________________________________________________________________

## name: docs-sync-and-policy-check description: "Use when behavior, standards, or CI policy changes require synchronized markdown updates across README, Instructions.md, and docs/."

# Docs Sync and Policy Check

## Goal

Keep documentation synchronized with real implementation and quality policy.

## Procedure

1. Compare changed behavior to current docs.
1. Update user-facing instructions first, then developer standards.
1. Keep policy statements precise and non-contradictory.
1. Verify markdown formatting with mdformat check path.

## Required Sync Targets

1. `README.md`
1. `Instructions.md`
1. `docs/development_standards.md`
1. Other docs under `docs/` when feature-specific behavior changes.

## Output

1. Updated doc file list.
1. Policy assertions verified against current lint/test setup.
