# Development & Standards

## Environment

- **OS**: Raspberry Pi OS (Debian-based)
- **Shell**: Bash
- **Runtime**: `ssmtp`, `mailutils`
- **Testing**: `bats-core`, `kcov`

## Testing & Coverage

### **Mandatory: 90% code coverage (overall and per-file in CI)**

```bash
# Run tests with coverage (updates badge automatically)
COVERAGE=1 ./tests/run_suite.sh

# Commit the updated badge
git add assets/coverage.svg
git commit -m "Update coverage badge"
```

The `run_suite.sh` script:

1. Runs all bats tests with kcov
1. Generates `coverage/cobertura.xml` (repo-root report dir; ignore rules use `/coverage/` so
   `scripts/coverage/` kcov drivers stay tracked and Docker-copied)
1. Auto-updates `assets/coverage.svg`
1. Warns if coverage < 90%

CI validation enforces both coverage and complexity gates:

1. Overall merged coverage >= 90%
1. Per-file coverage >= 90% for each covered script file
1. Overall complexity \<= 15
1. Per-file complexity \<= 15

## Coding Standards

- Use `set -e` for fail-fast
- Use `DEBIAN_FRONTEND=noninteractive`
- Capture stdout/stderr to logs
- Never leave system in inconsistent state
- Meet complexity thresholds through logic refactoring, not by removing useful comments.

## Linting & Formatting Standards

The project enforces a multi-layer lint gate:

1. `shellcheck` for shell correctness and safety (`tests/lint.sh` lints **git-tracked** `*.sh`
   via `git ls-files` — untracked scripts can pass locally and fail in CI once committed)
1. `shfmt` for shell formatting consistency
1. `bash -n` syntax validation for all shell scripts
1. `yamllint` for YAML and workflow structure
1. `actionlint` for GitHub Actions validation
1. `hadolint` for Dockerfile best practices
1. `mdformat --check` for Markdown formatting checks
1. GNU gettext catalog freshness (`scripts/i18n/extract_pot.sh --check`), seed check, and
   `scripts/i18n/check_catalog_quality.py` (no missing/fuzzy/English-carryover translations)
1. 140-character maximum line length enforced across shell, YAML, and Dockerfiles

Markdown lint is mandatory in CI strict mode, but markdown files do not have a max line-length requirement.

User-facing strings use `lib/i18n.sh` (`_pi_gettext` / `_pi_gettextf`). Domain:
`pi-maintenance-suite`. Tracked catalogs live under `po/` (Whisper-aligned 99 languages).
Generated `.mo` files under `locale/` are not tracked. Lookup uses a non-C base locale
(`PI_GETTEXT_BASE_LANG`, default `en_US.UTF-8`) so `LANGUAGE` is honored even when the
session is `C.UTF-8`; CI test images must generate `en_US.UTF-8`.

Run all checks locally:

```bash
# Preferred CI-parity gate (Docker required; same entrypoint Actions uses per stage)
./scripts/build-and-test.sh --full

# Host fallback
./tests/format.sh
STRICT_MODE=true ./tests/lint.sh
./tests/run_suite.sh
```

GitHub Actions stages call the same flags (`--lints-only`, `--coverage-only`, `--distro <image>`).
Matrix/coverage containers bind-mount the checkout; [`scripts/ensure_exec.sh`](../scripts/ensure_exec.sh)
marks scripts executable on the host and asserts `+x` in-container when UID mismatch blocks `chmod`.
Test images bake host `CI_UID`/`CI_GID` into user `pi`, and `run_docker_matrix.sh` runs containers
with `--user $(id -u):$(id -g)` so repo-root writes succeed on Actions runners.

## Documentation

- Update `README.md` for user-facing changes
- Update `Instructions.md` + `docs/` for AI/developer guidance
- Update `AGENTS.md` and affected agent skills/prompts/instructions whenever behavior or policy changes
- **Always** do markdown updates in the **same change set** as the code — never defer docs
- Suite version SSOT is the root `VERSION` file; keep GitHub release tags identical to its contents
- Add or update release description markdown in `docs/releases/vX.Y.Z.md` when preparing a tagged release (use the `prepare-release` skill; amend HEAD title/body to match)
