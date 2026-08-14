# Project Overview & Directory Structure

## Purpose

Bash scripts for automating Raspberry Pi maintenance with email reporting via Gmail/SSMTP.

## Directory Structure

```
├── scripts/           # Maintenance scripts + Docker CI helpers
├── lib/               # Shared helpers (os_pkg, mail_send)
├── tests/             # Bats tests with kcov coverage
├── docker/images/     # Lint + distro test Dockerfiles
├── assets/            # Coverage badge + email screenshots
├── docs/              # AI-friendly documentation
├── AGENTS.md          # Always-on agent rules
├── .agents/skills/    # Task playbooks (installer, matrix, pipeline, …)
├── .github/agents|skills|prompts|instructions/  # Copilot agent pack
├── install.sh         # Whiptail UI default; text fallback; --update cron-safe
└── uninstall.sh       # Cleanup script
```

## Key Features

- Cron-based automated scheduling
- Email reporting via SSMTP/Gmail
- Intelligent reboot detection
- Zero user input during execution
- **Self-healing auto-update**: repo [`VERSION`](../VERSION) is the SSOT; installed `.version` tracks it; updates via GitHub release tags + `install.sh --update` (cron-safe)
