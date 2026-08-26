______________________________________________________________________

## name: release-readiness description: Pre-merge or pre-release go/no-go checklist; release-notes and HEAD amend checks are N/A without a release target.

# Release Readiness

## Goal

Decide go/no-go for merge or tagged release.

## Modes

1. **Pre-merge** (no release target): run shared gates; report release-notes and HEAD-commit checks as **N/A**.
1. **Pre-release** (target `vX.Y.Z` / `RELEASE_TARGET` set): also require release notes and HEAD subject/body match.

## Shared checklist

1. `./scripts/build-and-test.sh --full` green (or equivalent CI).
1. Coverage ≥90% / complexity ≤15; `assets/coverage.svg` current.
1. Distro matrix lanes listed in `AGENTS.md` all present in CI + Dockerfiles.
1. Installer: whiptail default, text fallback, `--update` cron-safe.
1. Self-update + Samsung invariants still hold.
1. README / Instructions / docs / AGENTS / skills updated for this change.
1. UI remains English-only (`lib/ui_msg.sh`); no gettext catalog requirements.

## Release-only checklist (N/A in pre-merge)

1. Root `VERSION` equals `vX.Y.Z` and matches the branch / planned GitHub tag.
1. `docs/releases/vX.Y.Z.md` exists and matches the branch version (first line is `# …` H1 used as the GitHub Release title).
1. HEAD commit subject/body match the release title/description (amended only after explicit user confirmation via prepare-release).
1. Push the release tag only after the release commit has been merged into the default branch
   (`release.yml` requires the tag commit to be an ancestor of the default branch); that tag push
   publishes `docs/releases/vX.Y.Z.md` as the GitHub Release body.

## Related skill

Run [prepare-release](../prepare-release/SKILL.md) first when notes or the commit message still need updating.

## Output

Pass/fail/N/A table per checklist item + residual risks.
