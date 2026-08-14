# Agent Guide: Raspberry Pi Maintenance Automation Suite

This repository is **shell-first** and quality-gated by Dockerized lint + BATS tests.
Agents must optimize for safe Bash changes, deterministic tests, and CI parity.

## Project Overview

Bash scripts that automate Raspberry Pi (and compatible Debian/Ubuntu/Fedora/Rocky/Arch)
maintenance: OS updates, firmware, pip (Pi-only), Pi-Apps, Docker cleanup, Samsung NVMe
firmware, and self-update — with email reporting via ssmtp/msmtp.

- **Installer**: [`install.sh`](install.sh) — whiptail UI by default; classic text UI as
  automatic fallback; `install.sh --update` is non-interactive and cron-safe.
- **Shared libs**: [`lib/os_pkg.sh`](lib/os_pkg.sh) (apt/dnf/pacman), [`lib/mail_send.sh`](lib/mail_send.sh),
  [`lib/i18n.sh`](lib/i18n.sh) (GNU gettext UI localization).
- **Preferred local CI parity**: `./scripts/build-and-test.sh --full`.

## Agent Config Layout

| Path | Role |
| -------------------------------------------------------------------- | ---------------------------------------- |
| [`AGENTS.md`](AGENTS.md) | Always-on project law (this file) |
| [`.agents/skills/`](.agents/skills/) | On-demand task playbooks (`SKILL.md`) |
| [`.github/agents/`](.github/agents/) | Copilot/agent personas |
| [`.github/skills/`](.github/skills/) | Copilot skills (mirrors workflow skills) |
| [`.github/prompts/`](.github/prompts/) | Chat prompt templates |
| [`.github/instructions/`](.github/instructions/) | Path-scoped coding rules (`applyTo`) |
| [`.github/copilot-instructions.md`](.github/copilot-instructions.md) | Repo-wide Copilot context |
| [`.agent/instructions.md`](.agent/instructions.md) | Mandatory fix-lints-and-tests workflow |
| [`Instructions.md`](Instructions.md) | Human/AI technical handbook |

When behavior or policy changes, update **this file** and any affected skills/prompts/instructions
in the **same change set**.

## Always Update Markdown Docs

**Mandatory:** every code, test, CI, or policy change that alters behavior, commands, paths,
UI, supported distros, or contributor workflow **must** update the relevant markdown in the
**same change set**. Do not leave docs for a follow-up.

Update as applicable:

1. [`README.md`](README.md) — user-facing install/UI/features
1. [`Instructions.md`](Instructions.md) — AI/developer handbook
1. [`docs/*.md`](docs/) — overview, script logic, standards, releases
1. [`AGENTS.md`](AGENTS.md) — always-on agent rules (this file)
1. [`.agents/skills/**`](.agents/skills/) — skill playbooks that mention the changed behavior
1. [`.github/**` agent/skills/prompts/instructions](.github/) and [`.agent/instructions.md`](.agent/instructions.md)
1. [`docs/releases/vX.Y.Z.md`](docs/releases/) when preparing a versioned release (`prepare-release`)

Shipping code without matching markdown updates is incomplete work.

## UI Localization

- User-facing installer, uninstall, and maintenance email/UI strings use GNU gettext domain
  `pi-maintenance-suite`. Helpers live in [`lib/i18n.sh`](lib/i18n.sh)
  (`_pi_gettext` / `_pi_gettextf` / `_pi_ngettext` / `_pi_pgettext`).
- [`po/SUPPORTED_LANGUAGES`](po/SUPPORTED_LANGUAGES) is the Whisper-aligned 99-language SSOT;
  `po/*.po` is source of truth. Generated `.mo` files under `locale/` are **not** tracked;
  compile with [`scripts/i18n/build_mo.sh`](scripts/i18n/build_mo.sh) or via installer
  `_install_locale_catalogs` into `$INSTALL_DIR/locale`.
- Track [`po/pi-maintenance-suite.pot`](po/pi-maintenance-suite.pot) in git (`.gitignore` ignores
  `*.pot` with an explicit `!po/pi-maintenance-suite.pot` exception). Lint freshness
  (`scripts/i18n/extract_pot.sh --check`) requires the template to be **git-tracked** and
  byte-identical to a regenerate.
- UI language precedence is test-only `TEST_MODE=true`/`1` + `PI_UI_LANG`, then session
  `LC_MESSAGES` → `LANG` → `LANGUAGE`, then English msgids. Never set `LC_ALL` for UI lookup
  and never document `PI_UI_LANG` as an end-user setting.
- Catalog lookup forces a non-C base locale (`PI_GETTEXT_BASE_LANG`, default `en_US.UTF-8`)
  because GNU gettext **ignores** `LANGUAGE` when the process locale is `C` / `C.UTF-8`.
  Do not set lookup `LC_MESSAGES` to an ungenerated UI locale (that also collapses to C).
  Test Docker images must generate `en_US.UTF-8` (not `LANG=C.UTF-8` alone).
- Test-only hooks (never document for end users): `PI_I18N_FORCE_INLINE_STUBS`,
  `PI_UNINSTALL_ROOT_OVERRIDE`, `PI_I18N_REPO_ROOT_OVERRIDE`, `PI_I18N_SKIP_SYSTEM_LOCALE`,
  `PI_I18N_SKIP_REPO_LOCALE`, `PI_GETTEXT_BASE_LANG`.
- curl|bash fresh install may show English msgids before catalogs are downloaded/compiled;
  after `download_scripts` + `_install_locale_catalogs`, later wizard steps and the manager
  menu use the session locale.

## Always Update Translations

**Mandatory:** any add, edit, or remove of a gettext msgid (`_pi_gettext` / `_pi_gettextf` /
`_pi_ngettext` / `_pi_pgettext`) must update `po/pi-maintenance-suite.pot` **and every**
`po/*.po` listed in `po/SUPPORTED_LANGUAGES` in the **same change set**. Do not ship empty,
fuzzy, or English-copied msgstr for non-English locales. Incomplete catalog updates are
incomplete work (same as missing tests or stale docs).

Workflow:

1. Change the marked source string
1. `scripts/i18n/extract_pot.sh`
1. `scripts/i18n/sync_pos.sh` (seed + msgmerge)
1. Fill/update msgstr in all languages (`scripts/i18n/fill_catalogs.py` or manual expert fill)
1. `scripts/i18n/check_catalog_quality.py` and `msgfmt -c` (via `STRICT_MODE=true ./tests/lint.sh`)

Preserve printf placeholders; use `ngettext` for counts and `pgettext` for ambiguous labels;
keep package names, paths, cron fields, and protocol tokens untranslated.

## Core Rules

1. Keep changes minimal and scoped to the requested behavior.
1. **Always update markdown docs** (see above) in the same change set as code/test/CI edits.
1. **Always update translations** (see above) when changing marked gettext strings.
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

Stages: lint-in-docker → coverage gate (`debian:trixie`) → parallel distro matrix
(compat then e2e per lane). Compat exercises real text install + `--update` + uninstall;
e2e runs `tests/e2e/*.bats` and another install/`--update`/uninstall pass with `REAL_DEPS=1`.
Matrix fresh install uses `INSTALL_MATRIX_FRESH=1` via `scripts/matrix_install_flow.sh`
(requires `MATRIX_ALLOW_RM_INSTALL_DIR=1` and `INSTALL_DIR` under `/tmp/pi-scripts*`).

GitHub Actions [`.github/workflows/ci.yml`](.github/workflows/ci.yml) must call the **same**
entrypoint flags as local: `--lints-only`, `--coverage-only`, and `--distro <image>` (not raw
`lint-in-docker.sh` / `run_docker_matrix.sh` one-offs). Host + container executable prep uses
[`scripts/ensure_exec.sh`](scripts/ensure_exec.sh) so bind-mounted checkouts work when container
`USER pi` does not own the tree (GitHub Actions UID mismatch). Test images are built with
`CI_UID`/`CI_GID` matching the host and containers run `--user $(id -u):$(id -g)` so writes into
the bind-mounted repo (coverage badge, temp copies, kcov) succeed on Actions and locally.

Lint collects shell files via `git ls-files` — new `*.sh` must be tracked before local Docker lint
matches GitHub Actions. Ignore `/coverage/` and `/coverage_*/` only at repo root (never
`scripts/coverage/` kcov drivers); keep `.gitignore` and `.dockerignore` aligned on that rule.

Fallback / quick host checks:

```bash
./tests/format.sh
STRICT_MODE=true ./tests/lint.sh
./tests/run_suite.sh
```

Windows host: prefer `./scripts/build-and-test.sh --full` from WSL/Git Bash with Docker,
or `powershell -ExecutionPolicy Bypass -File .\tools\windows\run_tests_local.ps1 -NoCoverage`.

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
1. Fresh whiptail install offers explicit **Continue/Cancel** (welcome) and **Download/Cancel**
   before mutating `$INSTALL_DIR`, plus Esc/Cancel on email and task checklist steps.
1. `check_dependencies` installs `curl`, mail-transport (`ssmtp`/`mailutils` or `msmtp`), and `whiptail`/`newt`/`libnewt`.
1. Piped one-liner (`curl|bash`) must still prompt via `/dev/tty` when a TTY exists.
1. `install.sh --update` must stay **non-interactive** (deps + download only) for cron via `update_self.sh`.
1. Detection of “already installed” is `$INSTALL_DIR` directory presence (default `$HOME/pi-scripts`).
1. Interactive UI shows the suite version from root `VERSION` (via `read_suite_version`) in the
   header / whiptail welcome and main menu from the start of the session.
1. Preserve public function names used by BATS when refactoring UI (`configure_email_interactive`,
   `main_menu`, `run_fresh_install`, `manage_tasks_ui`, `read_input`, `run_interactive`, …).

## Pi vs Non-Pi Behavior

1. `IS_PI` detection uses device-tree / cpuinfo (overridable in tests via `TEST_MODE` + `MOCK_IS_PI`).
1. Non-Pi hosts **skip** Pi-only tasks (notably `update_pip.sh`) but **must still allow** firmware updates
   (`update_pi_firmware.sh` uses `fwupd` on non-Pi).
1. Pi-Apps scheduling remains user crontab; other tasks use root crontab.

## Package Manager Portability (`lib/os_pkg.sh`)

1. Families: `debian` (apt), `redhat` (dnf/yum), `arch` (pacman).
1. Logical deps map to OS packages (`whiptail` → `whiptail` / `newt` / `libnewt`; mail → ssmtp or msmtp).
1. Scripts that need packages must go through `pkg_install` / `logical_is_installed` — do not hardcode
   apt-only install paths in maintenance scripts.
1. `rpi_ensure_cron_path` (sourced with this lib) seeds a cron-friendly PATH unless `MOCK_DIR` is set,
   so BATS `path_hiding_cmds` is not undone by re-appending `/usr/bin`.
1. Keep `tests/component_tests_os_pkg.bats` aligned with mapping changes.

## Self-Update Invariants (`scripts/update_self.sh`)

1. **Repo version SSOT** is the root [`VERSION`](VERSION) file (`vMAJOR.MINOR.PATCH`).
1. GitHub release tags **must match** `VERSION` exactly (e.g. `v1.1.0`).
1. Installed copy is `$INSTALL_DIR/.version`, written by `install.sh` from `VERSION` (local tree or `$RAW_URL/VERSION`).
1. Fetch latest tag via Releases API; on mismatch download tagged `install.sh` **and** `VERSION`, then run
   `bash install.sh --update` — **never** pipe installer stdin for this path.
1. Email success / up-to-date / failure reports via mail helpers.
1. Covered by `tests/component_tests_self_update.bats`.

## Samsung Firmware Invariants (`scripts/update_samsung_ssd.sh`)

1. Prefer `fwupdmgr` (LVFS stable channel) first.
1. Fallback: scrape Samsung support page → download ISO → extract `fumagician` → apply.
1. Do **not** enable `lvfs-testing` / beta channels.
1. Download the firmware ISO via `mktemp` + mode `600` — never a predictable `/tmp` path (TOCTOU).
1. In tests and `REAL_DEPS=1` e2e: mock only hardware/destructive commands; never run real flash
   against CI hosts.

## Uninstall / Temp-File Safety (`uninstall.sh`)

1. Rewrite root/user crontabs using `mktemp` + mode `600` bak/new files — never hardcoded
   `/tmp/root_cron.*` or `/tmp/user_cron.*` paths (TOCTOU / crontab injection).

## Distro Matrix Governance

Supported CI lanes (Pi-capable OS families; Pi 3/4 class; Pi 5 support varies upstream):

1. `debian:trixie` (canonical coverage gate + Raspberry Pi OS family)
1. `ubuntu:26.04`
1. `fedora:44`
1. `rocky:9`
1. `archlinux:latest`

Dockerfiles live under `docker/images/tests/`. Matrix orchestration: `scripts/run_docker_matrix.sh`.
Adding/removing a lane requires coordinated updates to matrix script, CI workflow, Dockerfiles, and docs.

## Testing Conventions

1. BATS under `tests/`; shared mocks in `tests/setup_mocks.sh`.
1. Installer tests: `tests/install_*.bats` (including `install_whiptail.bats`).
1. Component tests per script area; e2e under `tests/e2e/` with `REAL_DEPS=1` for real packages.
1. Coverage via kcov + `tests/transform_coverage.py` (thresholds above).
1. Prefer deterministic mocks; isolate `INSTALL_DIR`, `SSMTP_CONF`, `REVALIASES`, `MOCK_DIR`.
1. Whiptail mock is controllable via `/tmp/mocks/whiptail_*` state files — exercise both
   whiptail success and text-fallback paths.

## Skills Index (`.agents/skills/`)

| Skill | Use when |
| ------------------------- | --------------------------------------------------------------------- |
| `code-linter` | Format/lint autofix then strict lint |
| `test-runner` | BATS + coverage/complexity gates |
| `pipeline-runner` | Full Docker CI parity until green |
| `installer-tester` | install.sh UI, fallback, `--update` |
| `distro-matrix-tester` | Distro Docker lanes / Dockerfiles |
| `samsung-firmware-tester` | Samsung SSD update paths |
| `self-update-tester` | Cron-safe self-update |
| `resolve-pr-comments` | Close every PR review thread via `gh` |
| `review-with-coderabbit` | User-gated CodeRabbit review/fix loop |
| `prepare-release` | Version from branch, `docs/releases/vX.Y.Z.md`, amend HEAD title/body |
| `release-readiness` | Go/no-go checklist before tag/merge |

## Files That Usually Need Coordinated Updates

1. Script logic: `scripts/*.sh`, `install.sh`, `uninstall.sh`, `lib/*.sh`
1. Tests: `tests/*.bats`, `tests/e2e/`, `tests/run_suite.sh`, `tests/setup_mocks.sh`, drivers
1. CI/Docker: `.github/workflows/ci.yml`, `docker/images/**`, `scripts/build-and-test.sh`,
   `scripts/run_docker_matrix.sh`, `scripts/lint-in-docker.sh`
1. Docs: `README.md`, `Instructions.md`, `docs/*.md`, **and agent files** (`AGENTS.md`, skills, prompts)

## PR Readiness Checklist

1. Docker lint passes.
1. Coverage gate ≥ 90% / complexity ≤ 15; badge updated if needed.
1. Distro matrix lanes pass (compat + e2e), including real install/uninstall in both stages.
1. Installer whiptail + text-fallback tests still pass; `--update` remains cron-safe.
1. **Markdown docs and agent skills/instructions updated in the same change** (never defer).
1. On versioned release branches: `prepare-release` wrote `docs/releases/vX.Y.Z.md` and amended HEAD title/body.
