# Project Overview & Directory Structure

## Purpose

Bash scripts for automating Raspberry Pi maintenance with email reporting via Gmail/SSMTP.

## Directory Structure

```
├── scripts/           # Maintenance scripts
│   ├── update_pi_os.sh
│   ├── update_pi_firmware.sh
│   ├── update_pip.sh
│   ├── update_pi_apps.sh
│   ├── docker_cleanup.sh
│   ├── update_samsung_ssd.sh
│   └── update_self.sh     # Auto-update; stores version in .version (release tag)
├── tests/             # Bats tests with kcov coverage
├── assets/            # Coverage badge + email screenshots
├── docs/              # AI-friendly documentation
├── install.sh         # One-liner installer (--update flag for non-interactive use)
└── uninstall.sh       # Cleanup script
```

## Key Features

- Cron-based automated scheduling
- Email reporting via SSMTP/Gmail
- Intelligent reboot detection
- Zero user input during execution
- **Self-healing auto-update**: tracks version via GitHub release tag; updates non-interactively via `install.sh --update` (cron-safe)
