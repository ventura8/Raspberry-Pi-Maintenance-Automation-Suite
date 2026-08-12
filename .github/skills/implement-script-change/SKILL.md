______________________________________________________________________

## name: implement-script-change description: Add or modify Bash behavior in install.sh, scripts/*, or lib/* while preserving safety, portability, and cron-safe update flows.

# Implement Script Change

## Goal

Apply Bash behavior changes safely with minimal regressions.

## Procedure

1. Keep modifications localized — avoid broad rewrites.
1. Preserve non-interactive and cron-safe paths (`install.sh --update`).
1. Use `lib/os_pkg.sh` for package installs; do not hardcode apt-only flows in maintenance scripts.
1. Prefer explicit branching and readable helpers over clever one-liners.
1. Reflect new behavior in matching BATS tests and mocks.
1. **Always update markdown** (README / Instructions / docs / AGENTS / skills) in the same change set.
1. **Always update translations** when changing `_pi_gettext*` strings (`.pot` + all `po/*.po`).
1. If UI/install behavior changes, follow `.agents/skills/installer-tester`.
1. Re-run format/lint and targeted tests, then broader suite or Docker full gate.

## Guardrails

1. No shellcheck/lint suppression comments.
1. Shell/YAML/Dockerfile line length ≤ 140.
1. Do not introduce interactive prompts into automated/cron paths.
1. Whiptail Cancel must not force text fallback.
1. Non-Pi must skip Pi-only tasks but keep firmware updates available.
1. Always update markdown docs in the same change set as code changes.
1. Always update all-language gettext catalogs when marked strings change.

## Validation

```bash
./tests/format.sh
STRICT_MODE=true ./tests/lint.sh
./tests/run_suite.sh
# Preferred when Docker available:
./scripts/build-and-test.sh --full
```
