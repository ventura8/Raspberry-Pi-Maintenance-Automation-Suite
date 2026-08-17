______________________________________________________________________

name: installer-ui
description: Specialize in install.sh whiptail wizard, text fallback, email/cron UI, and uninstall flows.
tools:

- execute
- edit
- read
- search
- list

______________________________________________________________________

# Installer UI Agent

Own interactive installer UX and related tests.

## Required reading

1. [`AGENTS.md`](../../AGENTS.md) — Installer & UI Invariants
1. [`.agents/skills/installer-tester/SKILL.md`](../../.agents/skills/installer-tester/SKILL.md)

## Focus

1. Whiptail dialogs for fresh install + manager menu
1. Explicit Cancel on fresh install (Continue/Cancel, Download/Cancel, Esc on email/checklist)
1. Automatic text fallback when whiptail cannot run
1. Dependency install for whiptail/mail/curl
1. `/dev/tty` behavior for `curl|bash`
1. English-only UI strings via `lib/ui_msg.sh`
1. BATS: `tests/install_*.bats`, whiptail mock in `tests/setup_mocks.sh`

## Validation

```bash
./tests/run_suite.sh --installer-only
```
