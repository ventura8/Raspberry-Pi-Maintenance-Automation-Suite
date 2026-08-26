# Agent Guide: Raspberry Pi Maintenance Automation Suite

This repository is **shell-first** and quality-gated by Dockerized lint + BATS tests. Agents must optimize for safe Bash changes, deterministic tests, and CI parity.

## Project Overview

Bash scripts that automate Raspberry Pi (and compatible Debian/Ubuntu/Fedora/Rocky/Arch) maintenance: OS updates, firmware, pip (Pi-only), Pi-Apps, Docker cleanup, Samsung NVMe firmware, and self-update — with email reporting via ssmtp/msmtp.

- **Installer**: [`install.sh`](install.sh) — whiptail UI by default; classic text UI as automatic fallback; `install.sh --update` is non-interactive and cron-safe.
- **Shared libs**: [`lib/os_pkg.sh`](lib/os_pkg.sh) (apt/dnf/pacman), [`lib/mail_send.sh`](lib/mail_send.sh), [`lib/ui_msg.sh`](lib/ui_msg.sh) (English-only UI message helpers).
- **Preferred local CI parity**: `./scripts/build-and-test.sh --full`.

## Agent Config Layout

| Path                                                                 | Role                                     |
| -------------------------------------------------------------------- | ---------------------------------------- |
| [`AGENTS.md`](AGENTS.md)                                             | Always-on project law (this file)        |
| [`.agents/skills/`](.agents/skills/)                                 | On-demand task playbooks (`SKILL.md`)    |
| [`.github/agents/`](.github/agents/)                                 | Copilot/agent personas                   |
| [`.github/skills/`](.github/skills/)                                 | Copilot skills (mirrors workflow skills) |
| [`.github/prompts/`](.github/prompts/)                               | Chat prompt templates                    |
| [`.github/instructions/`](.github/instructions/)                     | Path-scoped coding rules (`applyTo`)     |
| [`.github/copilot-instructions.md`](.github/copilot-instructions.md) | Repo-wide Copilot context                |
| [`.agent/instructions.md`](.agent/instructions.md)                   | Mandatory fix-lints-and-tests workflow   |
| [`Instructions.md`](Instructions.md)                                 | Human/AI technical handbook              |

When behavior or policy changes, update **this file** and any affected skills/prompts/instructions in the **same change set**.

## Always Update Markdown Docs

**Mandatory:** every code, test, CI, or policy change that alters behavior, commands, paths, UI, supported distros, or contributor workflow **must** update the relevant markdown in the **same change set**. Do not leave docs for a follow-up.

Update as applicable:

1. [`README.md`](README.md) — user-facing install/UI/features
1. [`Instructions.md`](Instructions.md) — AI/developer handbook
1. [`docs/*.md`](docs/) — overview, script logic, standards, releases
1. [`AGENTS.md`](AGENTS.md) — always-on agent rules (this file)
1. [`.agents/skills/**`](.agents/skills/) — skill playbooks that mention the changed behavior
1. [`.github/**` agent/skills/prompts/instructions](.github/) and [`.agent/instructions.md`](.agent/instructions.md)
1. [`docs/releases/vX.Y.Z.md`](docs/releases/) when preparing a versioned release (`prepare-release`)

Shipping code without matching markdown updates is incomplete work.

## UI Messages (English-only)

- User-facing installer, uninstall, and maintenance email/UI strings use [`lib/ui_msg.sh`](lib/ui_msg.sh) helpers (`_pi_gettext` / `_pi_gettextf` / `_pi_echo` / `_pi_echof`). These are English passthrough wrappers (sequential `%s` substitution); there are **no** gettext catalogs, `po/`, or locale installs.
- Do not reintroduce GNU gettext, `msgfmt` PO lints, or translation workflows unless explicitly requested.

## Core Rules

1. Keep changes minimal and scoped to the requested behavior.
1. **Always update markdown docs** (see above) in the same change set as code/test/CI edits.
1. Do **not** add lint suppressions, disables, or ignore directives for linters/formatters.
1. Preserve line-length policy: **140** for shell, YAML, and Dockerfiles. Markdown has no max-line constraint.
1. Prefer portable Bash that works in Linux CI and Docker-based local runs.
1. Avoid destructive operations unless explicitly requested.
1. Do not reduce complexity metrics by deleting useful comments; refactor logic instead.
1. Prefer Docker validation (`./scripts/build-and-test.sh --full`) over host-only checks when Docker is available.
1. Keep fixing until gates are green — never paper over failures.

## Required Local Validation

Preferred (Docker, matches CI):

```bash
./scripts/build-and-test.sh --full
```

Stages: lint-in-docker → coverage gate (`debian:trixie`) → parallel distro matrix (compat then e2e per lane). Compat exercises real text install + `--update` + uninstall; e2e runs `tests/e2e/*.bats` and another install/`--update`/uninstall pass with `REAL_DEPS=1`. Matrix fresh install uses `INSTALL_MATRIX_FRESH=1` via `scripts/matrix_install_flow.sh` (requires `MATRIX_ALLOW_RM_INSTALL_DIR=1` and `INSTALL_DIR` under `/tmp/pi-scripts*`).

GitHub Actions [`.github/workflows/ci.yml`](.github/workflows/ci.yml) must call the **same** entrypoint flags as local: `--lints-only`, `--coverage-only`, and `--distro <image>` (not raw `lint-in-docker.sh` / `run_docker_matrix.sh` one-offs). Host + container executable prep uses [`scripts/ensure_exec.sh`](scripts/ensure_exec.sh) so bind-mounted checkouts work when container `USER pi` does not own the tree (GitHub Actions UID mismatch). Test images are built with `CI_UID`/`CI_GID` matching the host and containers run `--user $(id -u):$(id -g)` so writes into the bind-mounted repo (coverage badge, temp copies, kcov) succeed on Actions and locally.

Lint collects shell files via `git ls-files` — new `*.sh` must be tracked before local Docker lint matches GitHub Actions. Ignore `/coverage/` and `/coverage_*/` only at repo root (never `scripts/coverage/` kcov drivers); keep `.gitignore` and `.dockerignore` aligned on that rule.

Fallback / quick host checks:

```bash
./tests/format.sh
STRICT_MODE=true ./tests/lint.sh
./tests/run_suite.sh
```

Windows host: prefer `./scripts/build-and-test.sh --full` from WSL/Git Bash with Docker, or `powershell -ExecutionPolicy Bypass -File .\tools\windows\run_tests_local.ps1 -NoCoverage`.

Live logs: tee long runs under `reports/distro-logs/` when iterating on matrix/pipeline failures.

## Quality Gates

1. Overall merged coverage **≥ 90%**
1. Per-file coverage **≥ 90%** for each covered script file
1. Overall complexity **≤ 15**
1. Per-file complexity **≤ 15**
1. Docker lint stack clean (shellcheck, shfmt, bash -n, yamllint, actionlint, hadolint, mdformat)
1. Distro matrix lanes pass (compat + e2e)
1. Commit updated `assets/coverage.svg` after coverage-affecting changes

## Installer & UI Invariants

1. Interactive UI defaults to **whiptail** (checklist / menu / inputbox / passwordbox / yesno / msgbox).
1. Classic **text UI** is the automatic fallback when whiptail is missing, fails to install, or cannot run.
1. User Cancel (whiptail rc 1/255) aborts or returns to menu — it does **not** force text fallback.
1. Fresh whiptail install offers explicit **Continue/Cancel** (welcome) and **Download/Cancel** before mutating `$INSTALL_DIR`, plus Esc/Cancel on email and task checklist steps.
1. `check_dependencies` installs `curl`, mail-transport (`msmtp`/`mailutils` or family equivalent; `ssmtp` only as legacy fallback), and `whiptail`/`newt`/`libnewt`.
1. Piped one-liner (`curl|bash`) must still prompt via `/dev/tty` when a TTY exists.
1. Fresh `curl|bash` with no adjacent/installed `lib/` bootstraps `os_pkg.sh` / `mail_send.sh` / `ui_msg.sh` from `$RAW_URL/lib/` before `check_dependencies` so `pkg_install` / `has_mail_sender` are defined.
1. `install.sh --update` must stay **non-interactive** (deps + download + quiet cron redirects) for cron via `update_self.sh`.
1. Detection of “already installed” is `$INSTALL_DIR` directory presence (default `$HOME/pi-scripts`).
1. Interactive UI shows the suite version from root `VERSION` (via `read_suite_version`) in the header / whiptail welcome and main menu from the start of the session.
1. Preserve public function names used by BATS when refactoring UI (`configure_email_interactive`, `main_menu`, `run_fresh_install`, `manage_tasks_ui`, `read_input`, `run_interactive`, …).
1. Shipped maintenance scripts must set `RECIPIENT_EMAIL="your_email@gmail.com"` (never a real address). `download_scripts` rewrites that assignment to the configured ssmtp/msmtp user (same pattern as `save_email_configuration`) so `--update` cannot restore a hardcoded inbox.

## Pi vs Non-Pi Behavior

1. `IS_PI` detection uses device-tree / cpuinfo (overridable in tests via `TEST_MODE` + `MOCK_IS_PI`).
1. Non-Pi hosts **skip** Pi-only tasks (notably `update_pip.sh`) but **must still allow** firmware updates (`update_pi_firmware.sh` uses `fwupd` on non-Pi).
1. Pi-Apps scheduling remains user crontab; other tasks use root crontab.

## Package Manager Portability (`lib/os_pkg.sh`)

1. Families: `debian` (apt), `redhat` (dnf/yum), `arch` (pacman).
1. Logical deps map to OS packages (`whiptail` → `whiptail` / `newt` / `libnewt`; mail → `msmtp` + `mailutils`/`s-nail`, without `msmtp-mta` so Debian/Arch cannot yank an existing `ssmtp` MTA mid-migration).
1. Scripts that need packages must go through `pkg_install` / `logical_is_installed` — do not hardcode apt-only install paths in maintenance scripts.
1. `rpi_ensure_cron_path` (sourced with this lib) seeds a cron-friendly PATH unless `MOCK_DIR` is set, so BATS `path_hiding_cmds` is not undone by re-appending `/usr/bin`.
1. Keep `tests/component_tests_os_pkg.bats` aligned with mapping changes.

## Self-Update Invariants (`scripts/update_self.sh`)

1. **Repo version SSOT** is the root [`VERSION`](VERSION) file (`vMAJOR.MINOR.PATCH`).
1. GitHub release tags **must match** `VERSION` exactly (e.g. `v1.1.0`).
1. Pushing a `v*` tag on a commit that is an ancestor of the default branch runs [`.github/workflows/release.yml`](.github/workflows/release.yml): it requires `docs/releases/vX.Y.Z.md`, uses that file as the GitHub Release body, and sets the release title from the file’s H1. Do not rely on auto-generated release notes.
1. Installed copy is `$INSTALL_DIR/.version`, written by `install.sh` from `VERSION` (local tree or `$RAW_URL/VERSION`).
1. Fetch latest tag via Releases API; on mismatch stage tagged `install.sh`, `VERSION`, and `lib/` in a `mktemp` directory, export `RAW_URL` for that tag, then run `bash "$stage_dir/install.sh" --update` — **never** pipe installer stdin for this path.
1. `--update` must source `$INSTALL_DIR/lib` when the installer tree has no sibling `lib/`, fail closed if `pkg_install` / `has_mail_sender` are undefined, and replace scripts via `mktemp` + `mv`.
1. Suite crontab lines use `>/dev/null 2>&1`; `--update` rewrites existing lines so cron MAILTO does not duplicate suite emails.
1. Email success / up-to-date / failure reports via mail helpers.
1. Covered by `tests/component_tests_self_update.bats`.

## Samsung Firmware Invariants (`scripts/update_samsung_ssd.sh`)

1. Prefer `fwupdmgr` (LVFS stable channel) first.
1. Fallback: scrape Samsung support page → download ISO → extract `fumagician` → apply.
1. Do **not** enable `lvfs-testing` / beta channels.
1. Download the firmware ISO via `mktemp` + mode `600` — never a predictable `/tmp` path (TOCTOU).
1. In tests and `REAL_DEPS=1` e2e: mock only hardware/destructive commands; never run real flash against CI hosts.

## Uninstall / Temp-File Safety (`uninstall.sh`)

1. Rewrite root/user crontabs using `mktemp` + mode `600` bak/new files — never hardcoded `/tmp/root_cron.*` or `/tmp/user_cron.*` paths (TOCTOU / crontab injection).

## Distro Matrix Governance

Supported CI lanes (Pi-capable OS families; Pi 3/4 class; Pi 5 support varies upstream):

1. `debian:trixie` (canonical coverage gate + Raspberry Pi OS family)
1. `ubuntu:26.04`
1. `fedora:44`
1. `rocky:9`
1. `archlinux:latest`

Dockerfiles live under `docker/images/tests/`. Matrix orchestration: `scripts/run_docker_matrix.sh`. Adding/removing a lane requires coordinated updates to matrix script, CI workflow, Dockerfiles, and docs.

## Testing Conventions

1. BATS under `tests/`; shared mocks in `tests/setup_mocks.sh`.
1. Installer tests: `tests/install_*.bats` (including `install_whiptail.bats`).
1. Component tests per script area; e2e under `tests/e2e/` with `REAL_DEPS=1` for real packages.
1. Coverage via kcov + `tests/transform_coverage.py` (thresholds above).
1. Prefer deterministic mocks; isolate `INSTALL_DIR`, `SSMTP_CONF`, `REVALIASES`, `MOCK_DIR`.
1. Whiptail mock is controllable via `/tmp/mocks/whiptail_*` state files — exercise both whiptail success and text-fallback paths.

## Skills Index (`.agents/skills/`)

| Skill                     | Use when                                                                                                                |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `code-linter`             | Format/lint autofix then strict lint                                                                                    |
| `test-runner`             | BATS + coverage/complexity gates                                                                                        |
| `pipeline-runner`         | Full Docker CI parity until green                                                                                       |
| `installer-tester`        | install.sh UI, fallback, `--update`                                                                                     |
| `distro-matrix-tester`    | Distro Docker lanes / Dockerfiles                                                                                       |
| `samsung-firmware-tester` | Samsung SSD update paths                                                                                                |
| `self-update-tester`      | Cron-safe self-update                                                                                                   |
| `resolve-pr-comments`     | Close every PR review thread via `gh`                                                                                   |
| `review-with-coderabbit`  | User-gated CodeRabbit review/fix loop                                                                                   |
| `prepare-release`         | Version from branch, `docs/releases/vX.Y.Z.md`; amend HEAD title/body only after explicit confirmation (not by default) |
| `release-readiness`       | Go/no-go checklist before tag/merge                                                                                     |

## Files That Usually Need Coordinated Updates

1. Script logic: `scripts/*.sh`, `install.sh`, `uninstall.sh`, `lib/*.sh`
1. Tests: `tests/*.bats`, `tests/e2e/`, `tests/run_suite.sh`, `tests/setup_mocks.sh`, drivers
1. CI/Docker: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `docker/images/**`, `scripts/build-and-test.sh`, `scripts/run_docker_matrix.sh`, `scripts/lint-in-docker.sh`
1. Docs: `README.md`, `Instructions.md`, `docs/*.md`, **and agent files** (`AGENTS.md`, skills, prompts)

## PR Readiness Checklist

1. Docker lint passes.
1. Coverage gate ≥ 90% / complexity ≤ 15; badge updated if needed.
1. Distro matrix lanes pass (compat + e2e), including real install/uninstall in both stages.
1. Installer whiptail + text-fallback tests still pass; `--update` remains cron-safe.
1. **Markdown docs and agent skills/instructions updated in the same change** (never defer).
1. On versioned release branches: `prepare-release` wrote `docs/releases/vX.Y.Z.md`; amend HEAD title/body only after explicit confirmation.
1. After merge to the default branch, pushing tag `vX.Y.Z` (matching `VERSION`) lets `release.yml` publish the GitHub Release from that notes file.
