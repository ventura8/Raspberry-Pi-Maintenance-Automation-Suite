# AI Instructions: Raspberry Pi Maintenance & Automation Suite

Technical guidance for AI agents and developers working on this project.

> **AI Agents**: Start with [AGENTS.md](AGENTS.md). Use playbooks under [.agents/skills/](.agents/skills/). Also see [.agent/instructions.md](.agent/instructions.md), [.github/copilot-instructions.md](.github/copilot-instructions.md), and [.github/prompts/README.md](.github/prompts/README.md).
>
> **Mandatory:** whenever you change code, tests, or CI, update the relevant markdown (`README.md`, `Instructions.md`, `docs/*`, `AGENTS.md`, skills/prompts) in the **same change set**.

## Agent layout

| Path                                           | Role                              |
| ---------------------------------------------- | --------------------------------- |
| [AGENTS.md](AGENTS.md)                         | Always-on project law             |
| [.agents/skills/](.agents/skills/)             | Domain + quality + process skills |
| [.github/agents/](.github/agents/)             | Copilot/agent personas            |
| [.github/skills/](.github/skills/)             | Copilot workflow skills           |
| [.github/prompts/](.github/prompts/)           | Chat prompt templates             |
| [.github/instructions/](.github/instructions/) | Path-scoped coding rules          |

## Coverage Requirement

> **Mandatory**: Maintain a minimum of **90% code coverage**.

CI enforces:

- Overall merged coverage ≥ 90%
- Per-file coverage ≥ 90% for each covered script file
- Overall complexity ≤ 15
- Per-file complexity ≤ 15
- Badge updates via `./scripts/build-and-test.sh --coverage-only` or `COVERAGE=1 ./tests/run_suite.sh`
- Always commit `assets/coverage.svg` after coverage-affecting changes

## CI Pipeline

Preferred local gate matching GitHub Actions:

```bash
./scripts/build-and-test.sh --full
```

Actions jobs call the same entrypoint per stage (`--lints-only`, `--coverage-only`, `--distro <image>`). Executable prep is shared via `scripts/ensure_exec.sh`. Test images bake host `CI_UID`/`CI_GID` into user `pi`, and matrix runs use `--user $(id -u):$(id -g)` so bind-mounted checkout writes work on GitHub Actions (runner UID often ≠ 1000).

Stages: Docker lint → coverage on `debian:trixie` → parallel distro matrix (`debian:trixie`, `ubuntu:26.04`, `fedora:44`, `rocky:9`, `archlinux:latest`; Pi 3/4 class support, Pi 5 varies by distro) with compat then e2e in each lane. Compat runs a real text install, `--update`, and uninstall; e2e runs `tests/e2e/*.bats` plus another install/`--update`/uninstall pass under `REAL_DEPS=1`.

## Automatic Dependency Installation

Scripts use `lib/os_pkg.sh` to install dependencies via `apt`, `dnf`, or `pacman`. `msmtp` (which verifies the SMTP server's TLS certificate) is the preferred mailer on every OS family, including Debian-family systems; `ssmtp` is only installed/used as a fallback when `msmtp` is unavailable or has no usable default account.

The interactive installer (`install.sh`) installs UI/runtime dependencies up front: `curl`, mail-transport, and `whiptail`. For `curl|bash` with no adjacent or installed `lib/`, it fetches `os_pkg.sh` / `mail_send.sh` / `ui_msg.sh` from `$RAW_URL/lib/` before `check_dependencies`. The suite version from root `VERSION` is shown from the start (text header and whiptail welcome/menu). Whiptail fresh install offers **Continue/Cancel** and **Download/Cancel** (plus Esc on email/checklist) so the user can abort without completing setup. If whiptail cannot be installed or cannot run, the installer automatically uses the classic text UI. `install.sh --update` remains non-interactive and cron-safe.

Maintenance scripts ship `RECIPIENT_EMAIL="your_email@gmail.com"`. `download_scripts` rewrites that assignment to the configured ssmtp/msmtp user (same `RECIPIENT_EMAIL="..."` substitution as `save_email_configuration`), so fresh install and `--update` never leave a hardcoded third-party inbox.

## Samsung SSD Firmware Updates

The `update_samsung_ssd.sh` script dynamically scrapes Samsung's official firmware page to find the latest firmware for detected NVMe SSDs. Supported models include 9100/990/980/970/960/950 series.

**Key Implementation Notes:**

- Primary method: `fwupdmgr` (LVFS)
- Fallback: Scrapes `https://semiconductor.samsung.com/consumer-storage/support/tools/`
- Extracts `fumagician` from ISO's `initrd` to apply updates
- No hardcoded firmware versions - always fetches latest
- Skill playbook: [.agents/skills/samsung-firmware-tester/SKILL.md](.agents/skills/samsung-firmware-tester/SKILL.md)

## Self-Update Mechanism

The suite includes a self-healing capability (`scripts/update_self.sh`) that ensures installations stay current.

- **Version SSOT**: repo-root [`VERSION`](VERSION) file (`vMAJOR.MINOR.PATCH`). GitHub release tags must match it.
- **Automated GitHub Release**: pushing tag `vX.Y.Z` runs [`.github/workflows/release.yml`](.github/workflows/release.yml), which publishes [`docs/releases/vX.Y.Z.md`](docs/releases/) as the release body (H1 = title). Tag commit must be an ancestor of the default branch.
- **Installed copy**: `install.sh` writes `$INSTALL_DIR/.version` from local `VERSION` (or `$RAW_URL/VERSION`).
- **Update Logic**:
  1. `update_self.sh` checks the GitHub API (`releases/latest`).
  1. Compares the remote tag with the local `.version` file.
  1. On mismatch: stages tagged `install.sh`, `VERSION`, and `lib/` in a temp directory, exports `RAW_URL` for that tag, then runs `bash install.sh --update` (no stdin pipe). `--update` sources `$INSTALL_DIR/lib` when the installer has no sibling `lib/`, replaces scripts atomically (`mktemp` + `mv`), and rewrites crontab lines to `>/dev/null 2>&1`.
- **Notifications**: success / up-to-date / failure emails.
- **Testing**: `tests/component_tests_self_update.bats`
- **Skill**: [.agents/skills/self-update-tester/SKILL.md](.agents/skills/self-update-tester/SKILL.md)

## Documentation Index

- [Project Overview & Directory Structure](docs/project_overview.md)
- [Script Logic & Functionality](docs/script_logic.md)
- [Development & Standards](docs/development_standards.md)
- [Release Notes (GitHub description)](docs/releases/v1.1.2.md) — prepare via `.agents/skills/prepare-release`; published automatically by `.github/workflows/release.yml` when the matching tag is pushed
- [Prompt Templates for Chat Workflows](.github/prompts/README.md)
