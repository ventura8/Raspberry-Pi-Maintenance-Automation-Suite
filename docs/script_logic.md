# Script Logic & Functionality

Each script: executes commands → captures logs → sends email → handles reboots.

______________________________________________________________________

## Scripts

### `update_pi_os.sh`

- `apt-get update` + `full-upgrade` + `autoremove`
- Uses `DEBIAN_FRONTEND=noninteractive`
- Checks `/var/run/reboot-required`

### `update_pi_firmware.sh`

- **(Raspberry Pi and Linux)**: Supports both Pi 4/5 EEPROM and standard Linux firmware.
- Checks for `rpi-eeprom-update -a` first (Pi specific).
- Falls back to `fwupdmgr` (Standard Linux) if Pi tool missing.
- Refreshes metadata, checks updates, installs, and parses output for reboot requirements.

### `update_pip.sh`

- **(Raspberry Pi Only)**: Disabled on other systems to protect system packages.
- `pip3 list --outdated` + upgrade each
- Bypasses PEP 668 with `--break-system-packages`
- Skips upgrading `pip` itself

### `update_pi_apps.sh`

- `updater cli-yes` (non-interactive)
- Must run as local user (not root)

### `docker_cleanup.sh`

- `docker system prune -f --volumes`
- Auto-detects `buildx` vs legacy `builder prune`

### `update_samsung_ssd.sh`

- Primary path: `fwupdmgr` via LVFS (stable channel only)
- Fallback: scrapes Samsung's official firmware page, downloads ISO, extracts and runs `fumagician`
- Uses `nvme-cli` to identify connected NVMe SSDs

### `update_self.sh`

- Compares local `.version` file (stores **release tag**, e.g. `v1.0.1`) against latest GitHub release tag via the Releases API
- On update available: downloads `install.sh` tagged at the remote version, runs `bash install.sh --update` (non-interactive; safe in cron — no `/dev/tty` access)
- On success: writes the new release tag to `.version`; sends success email
- On any failure: sends failure email via `ssmtp`
- **Cron safety**: installer is invoked directly with no stdin pipe — piping caused `No such device or address` on `/dev/tty` in cron environments
