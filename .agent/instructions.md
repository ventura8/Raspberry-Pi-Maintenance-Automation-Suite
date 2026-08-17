# AI Agent Instructions

Mandatory workflow for agents working on this Bash / BATS / Dockerized suite.

## Fix lints and tests (order)

1. Prefer a single pass that addresses lint + tests together when the change set is small.
1. **Format first**: `./tests/format.sh`
1. **Lint next**: prefer `./scripts/lint-in-docker.sh` (CI parity). Host fallback:
   `STRICT_MODE=true ./tests/lint.sh`
1. **Tests**: prefer `./scripts/build-and-test.sh --full`. Host fallback: `./tests/run_suite.sh`
1. **Coverage**: overall and per-file ≥ **90%**; complexity ≤ **15**. Update `assets/coverage.svg`
   when coverage changes.
1. Never add lint suppressions or lower gates to pass.

## Project realities (not Python)

1. This repo is **Bash-first**. Do not assume flake8/mypy/pytest workflows.
1. Mocks are shell stubs under `tests/setup_mocks.sh` / `/tmp/mocks`, not Python `unittest.mock`.
1. Windows agents should use WSL/Git Bash + Docker, or
   `tools/windows/run_tests_local.ps1 -NoCoverage`.

## Invariants to protect

1. `install.sh --update` remains non-interactive and cron-safe (no stdin pipe).
1. Maintenance scripts ship `RECIPIENT_EMAIL="your_email@gmail.com"`; `download_scripts` rewrites that assignment to the configured mail user.
1. Whiptail is default UI; classic text UI is automatic fallback only when whiptail cannot run.
1. Distro matrix and `lib/os_pkg.sh` stay aligned for apt/dnf/pacman.
1. **Always update markdown** (`README.md`, `Instructions.md`, `docs/*`, `AGENTS.md`, skills/prompts)
   in the **same change set** as code/test/CI edits — never leave docs for later.
1. UI strings are English-only via `lib/ui_msg.sh` — do not add gettext catalogs or PO lints.

## Authoritative docs

1. [`AGENTS.md`](../AGENTS.md) — always-on rules + skill index
1. [`.agents/skills/`](../.agents/skills/) — task playbooks
1. [`Instructions.md`](../Instructions.md) — technical handbook

## Quick commands

```bash
./scripts/build-and-test.sh --full
./tests/run_suite.sh --installer-only
COVERAGE=1 ./tests/run_suite.sh
```
