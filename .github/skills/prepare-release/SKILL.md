______________________________________________________________________

## name: prepare-release description: Prepare release from current branch version — sync VERSION SSOT, docs/releases notes; amend HEAD only after explicit confirmation.

# Prepare Release (Copilot)

Follow the full playbook:

[`.agents/skills/prepare-release/SKILL.md`](../../../.agents/skills/prepare-release/SKILL.md)

## Quick steps

1. Read/validate root `VERSION` as suite SSOT (`vMAJOR.MINOR.PATCH`); use `VERSION_OVERRIDE` only when explicitly provided and independently validated.
1. Parse/confirm `vX.Y.Z` from current branch name (must match `VERSION` unless override).
1. Write `docs/releases/vX.Y.Z.md` (GitHub Release body).
1. Sync README / Instructions / standards links to that path.
1. Stage release docs (+ `VERSION` + intended release files).
1. Ask for explicit amend confirmation immediately before rewriting HEAD (skill invocation alone is **not** authorization). On confirm: `git commit --amend` must update **both** subject (title `vX.Y.Z: …`) **and** body (description) to match `docs/releases/vX.Y.Z.md` — never leave a merge/PR/placeholder subject with a correct tree.
1. Show `git log -1` and note if merge / tag push is still needed — tag `vX.Y.Z` only after the tagged commit has been merged into the default branch; pushing that tag triggers `.github/workflows/release.yml` to publish `docs/releases/vX.Y.Z.md` (do not push unless asked).
