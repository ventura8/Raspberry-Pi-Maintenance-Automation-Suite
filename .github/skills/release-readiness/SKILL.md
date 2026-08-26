______________________________________________________________________

## name: release-readiness description: Pre-merge or pre-release checklist; release-notes and HEAD amend checks are N/A without a release target.

# Release Readiness

## Goal

Decide go/no-go for merge or tagged release.

## Modes

1. **Pre-merge** (no `RELEASE_TARGET`): shared gates only; report release-notes and HEAD-commit checks as **N/A**.
1. **Pre-release** (`RELEASE_TARGET` / `vX.Y.Z` set): also require notes + HEAD metadata.

## Shared checklist

1. `./scripts/build-and-test.sh --full` green (or equivalent CI).
1. Coverage ≥90% / complexity ≤15; `assets/coverage.svg` current.
1. Distro matrix lanes listed in `AGENTS.md` all present in CI + Dockerfiles.
1. Installer: whiptail default, text fallback, `--update` cron-safe.
1. Self-update + Samsung invariants still hold.
1. README / Instructions / docs / AGENTS / skills updated for this change.

## Release-only checklist (N/A in pre-merge)

1. Root `VERSION` equals `vX.Y.Z` and matches the branch / planned GitHub tag.
1. Release notes exist at `docs/releases/vX.Y.Z.md` (from `prepare-release`); first line must be an H1
   (`# …`) matching `.github/workflows/release.yml` title validation; tagging publishes that file.
1. Push the release tag only after the release commit has been merged into the default branch
   (`release.yml` requires the tag commit to be an ancestor of the default branch).
1. HEAD commit subject/body match the release title/description (amend only after explicit confirmation).

## Related skill

Use [`.agents/skills/prepare-release/SKILL.md`](../../../.agents/skills/prepare-release/SKILL.md) to generate notes; amend only after explicit user confirmation.

## Output

Pass/fail/N/A table per checklist item + residual risks.
