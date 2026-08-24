# Copilot Instructions

## Project context

Bash maintenance automation for Raspberry Pi and compatible Linux systems (Debian/Ubuntu/Fedora/Rocky/Arch), with BATS tests and Dockerized CI (`./scripts/build-and-test.sh --full`).

Authoritative rules: [`AGENTS.md`](../AGENTS.md). Task playbooks: [`.agents/skills/`](../.agents/skills/).

## Engineering expectations

1. Prefer simple, explicit Bash over clever one-liners.
1. Keep behavior deterministic under `tests/setup_mocks.sh`.
1. Maintain Pi and non-Pi paths (skip Pi-only tasks on non-Pi; keep firmware updates).
1. Keep email/reporting and reboot signaling stable unless explicitly changing them.
1. Use `lib/os_pkg.sh` for portable package installs; `lib/mail_send.sh` for mail where applicable.
1. Use `lib/ui_msg.sh` for user-facing strings (`_pi_gettext` / `_pi_gettextf`); English-only — no catalogs.

## Quality gates

1. No lint/formatter suppressions or broad ignores.
1. Line length ≤ 140 for shell, YAML, Dockerfiles (Markdown unrestricted).
1. Coverage ≥ 90% overall and per-file; complexity ≤ 15 overall and per-file.
1. Meet complexity via refactor, never by deleting useful comments.
1. Prefer Docker gates over host-only validation when Docker is available.

## Installer / CI specifics

1. Whiptail default UI; text UI automatic fallback when whiptail cannot run.
1. `install.sh --update` is non-interactive and must remain cron-safe for `update_self.sh` (stage tagged installer + `lib/` in `mktemp`, source `$INSTALL_DIR/lib` as fallback, atomic script replace, crontab `>/dev/null 2>&1`).
1. Maintenance scripts ship `RECIPIENT_EMAIL="your_email@gmail.com"`; `download_scripts` rewrites that assignment to the configured mail user.
1. Suite version SSOT is root `VERSION`; GitHub tags and `$INSTALL_DIR/.version` must match it.
1. Distro matrix: `debian:trixie`, `ubuntu:26.04`, `fedora:44`, `rocky:9`, `archlinux:latest`.

## Documentation discipline

**Always** update markdown in the **same change set** as code, tests, or CI edits that change behavior, commands, paths, UI, distros, or contributor workflow. Incomplete without docs.

When behavior or standards change, update:

1. `README.md`
1. `Instructions.md`
1. `docs/*` as needed
1. `AGENTS.md` and affected `.agents/skills/**` / `.github/**` agent configs
1. `.agent/instructions.md` when the mandatory agent workflow changes
1. `docs/releases/vX.Y.Z.md` when preparing a versioned release (published by `.github/workflows/release.yml` on tag push after the release commit is merged into the default branch)
