______________________________________________________________________

## name: prepare-release description: Prepare a versioned release from the current branch — sync markdown, write GitHub release notes under docs/releases/, and amend HEAD commit title/body to match.

# Prepare Release Skill

Use when the user asks to prepare a release, cut release notes, or finalize the current versioned branch commit for tagging/GitHub Release.

## Goals

1. Derive the release version from the **current git branch name** (must match root `VERSION`).
1. Set/confirm the root [`VERSION`](../../../VERSION) file to that version (repo **single source of truth**).
1. Update project markdown that should mention the new version / release notes link.
1. Create/update a GitHub release description markdown under `docs/releases/`.
1. **Amend** the current HEAD commit so its **subject and body** match the release title and description —
   **only after explicit user confirmation immediately before rewriting HEAD**. Invoking this skill is
   **not** amend authorization.

## Version from branch

Parse `git branch --show-current`:

| Branch example | Version |
| ---------------- | -------------------------------- |
| `feature/v1.1.0` | `v1.1.0` |
| `release/v1.1.0` | `v1.1.0` |
| `v1.1.0` | `v1.1.0` |
| `feature/1.1.0` | `v1.1.0` (normalize leading `v`) |

Rules:

1. Extract the first semver-like token `MAJOR.MINOR.PATCH` (optional leading `v`).
1. Normalize to **`vMAJOR.MINOR.PATCH`** (always include the `v` prefix for tags and docs).
1. If no version can be parsed, **stop** and ask the user for the version or a correctly named branch.
1. Write that exact string (plus trailing newline) into the root **`VERSION`** file — this is the suite SSOT.
1. GitHub release tags and `$INSTALL_DIR/.version` must match `VERSION`. Do not keep a second competing version constant in scripts.

## Workflow

### 1) Inspect repo state

```bash
git branch --show-current
git status -sb
git log -1 --format='%H%n%an <%ae>%n%s%n%n%b'
git rev-parse --abbrev-ref @{u} 2>/dev/null || true
git status -sb | head -5
```

Collect:

1. Parsed `VERSION` (e.g. `v1.1.0`)
1. Whether root `VERSION` file already matches (update it if not)
1. Whether working tree has release-related changes to include
1. Whether HEAD has been pushed (`branch` tracks remote and is not ahead-only)

### 2) Draft release content from the diff

Build the story from:

```bash
git log --oneline main..HEAD   # or master if that is the default base
git diff main...HEAD           # full branch delta
git diff                       # unstaged/staged local edits to include
```

Write a release title:

```text
vX.Y.Z: <short why-focused summary>
```

Write a GitHub-ready body using the structure in [examples.md](examples.md) (Summary, What Changed, Validation, Breaking Changes, Notes).

### 3) Update markdown docs

Ensure:

```text
VERSION                    # exactly vX.Y.Z + newline
docs/releases/vX.Y.Z.md
```

The `VERSION` file **is** the suite version SSOT. The release markdown **is** the GitHub Release description source (paste/body for `gh release create`).

Also sync references when they exist / are relevant:

1. [`Instructions.md`](../../../Instructions.md) — release notes link in the Documentation Index
1. [`README.md`](../../../README.md) — any release-notes / version pointers
1. [`docs/development_standards.md`](../../../docs/development_standards.md) — path must say `docs/releases/`
1. [`docs/project_overview.md`](../../../docs/project_overview.md) — only if it cites the latest release
1. Prior incorrect paths like `docs/release/` or `*-github-description.md` → point at `docs/releases/vX.Y.Z.md`

Do **not** invent user-facing feature claims that are not in the branch diff.

### 4) Stage release artifacts

```bash
git add VERSION docs/releases/vX.Y.Z.md
# plus any markdown path fixes / synced docs from step 3
# plus any other intentional release files already modified on the branch
git add -A  # only if the user intends the whole working tree in this release commit
```

Prefer staging explicitly when the tree mixes unrelated WIP. For a dedicated release branch, including the full intended change set is normal.

### 5) Amend HEAD commit title + description (opt-in)

Prepare release metadata (VERSION, `docs/releases/…`, synced markdown) **without** amending by default.
Ask the user to explicitly confirm amend immediately before rewriting HEAD. Skill invocation alone
is **not** authorization.

**Amend only when all are true:**

1. User explicitly confirmed amend in this turn (not merely “run prepare-release”).
1. `HEAD` is the release commit on the current version branch (subject often already starts with `vX.Y.Z` or is a placeholder).
1. Amend is used to refresh **message and included files**, not to rewrite unrelated history.
1. If the branch **was already pushed** and amend rewrites the remote tip, **warn** and only force-push if the user explicitly confirms (`git push --force-with-lease`).

**Never:**

1. Update git config
1. Amend with `--no-verify` unless the user explicitly demands it
1. Force-push to `main`/`master`
1. Treat “follow prepare-release skill” as standing amend permission

If the user declines amend, leave HEAD unchanged and report that they must commit/amend separately before tag/`gh release create`.

Commit via HEREDOC (subject + body):

```bash
git commit --amend -m "$(cat <<'EOF'
vX.Y.Z: short summary of the release

Longer body that can mirror the Summary section of docs/releases/vX.Y.Z.md.
Keep the subject ≤ ~72 chars when practical; put detail in the body.

EOF
)"
```

Include staged files in the amend (default `git commit --amend` without `--no-edit` after `git add`).

If there is **no** suitable HEAD to amend (empty repo / wrong branch / user wants a new commit instead), create a **new** commit with the same message format rather than amending unrelated history — and say so.

### 6) Verify

```bash
git log -1 --format='%s%n%n%b'
git status -sb
test -f docs/releases/vX.Y.Z.md
test "$(tr -d '[:space:]' < VERSION)" = "vX.Y.Z"
```

Optional next steps (do **not** do unless asked):

1. `gh release create vX.Y.Z --title "…" --notes-file docs/releases/vX.Y.Z.md`
1. Tag `vX.Y.Z` and push
1. Open/update PR

## Hard rules

1. Version comes from the **branch name**, normalized to `vMAJOR.MINOR.PATCH`, and is written to root **`VERSION`** (SSOT).
1. GitHub description path is always `docs/releases/vX.Y.Z.md`.
1. Amend updates both **title (subject)** and **description (body)** — only after explicit user confirmation.
1. Keep release notes accurate to the branch diff; no marketing fluff.
1. Run or recommend `release-readiness` / `./scripts/build-and-test.sh --full` before tagging if tests were not just validated.
1. After preparing the release, ensure agent docs that mention release paths stay consistent (`AGENTS.md`, skills, Instructions).
1. Remember the global rule: **any** behavior change requires markdown updates in the same change set (see `AGENTS.md` → Always Update Markdown Docs).

## Output to the user

1. Parsed version + branch + `VERSION` file contents
1. Path of the release markdown written
1. Other markdown files updated
1. New `git log -1` subject/body
1. Whether push/`gh release create` is still pending
1. Force-push warning if HEAD was already on the remote

## Additional resources

- [examples.md](examples.md) — title/body templates and branch→version examples
- Companion checklist: [release-readiness](../release-readiness/SKILL.md) (go/no-go before tag)
- Copilot mirror: [`.github/skills/prepare-release/SKILL.md`](../../../.github/skills/prepare-release/SKILL.md)
