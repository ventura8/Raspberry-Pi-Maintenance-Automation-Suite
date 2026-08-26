# Prepare Release — Examples

## Branch → version

| Branch                   | Version                       |
| ------------------------ | ----------------------------- |
| `feature/v1.1.0`         | `v1.1.0`                      |
| `release/v1.2.0`         | `v1.2.0`                      |
| `v1.0.4`                 | `v1.0.4`                      |
| `feature/1.1.0-whiptail` | `v1.1.0` (first semver token) |

## Commit subject

```text
v1.1.0: whiptail installer UI, Docker matrix, and full agent skill pack
```

## `docs/releases/v1.1.0.md` skeleton

```markdown
# v1.1.0: whiptail installer UI, Docker matrix, and full agent skill pack

### Summary

Short paragraph of why this release exists.

### What Changed

#### 1. Area Name

- Bullet of user/developer-visible change.
- Another bullet.

Files:

- `path/one`
- `path/two`

### Validation

- `./scripts/build-and-test.sh --full` (or note what actually ran).

### Breaking Changes

- None. (or list them)

### Notes

- Any migration/operator notes.
```

## Amend HEREDOC

```bash
git commit --amend -m "$(cat <<'EOF'
v1.1.0: whiptail installer UI, Docker matrix, and full agent skill pack

Whiptail is the default installer UI with classic text fallback. Docker distro
matrix covers Pi-capable OS families. Agent skills/docs are expanded for CI parity.

EOF
)"
```

## GitHub release (only when user asks)

```bash
gh release create v1.1.0 \
  --title "v1.1.0: whiptail installer UI, Docker matrix, and full agent skill pack" \
  --notes-file docs/releases/v1.1.0.md
```
