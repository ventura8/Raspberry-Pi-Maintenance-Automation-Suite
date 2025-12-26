# Script Logic & Functionality

Each script: executes commands → captures logs → sends email → handles reboots.

---

## Scripts

### `update_pi_os.sh`
- `apt-get update` + `full-upgrade` + `autoremove`
- Uses `DEBIAN_FRONTEND=noninteractive`
- Checks `/var/run/reboot-required`

### `update_pi_firmware.sh`
- `rpi-eeprom-update -a` (Pi 4/5 only)
- Compares versions before/after, reboots if changed

### `update_pip.sh`
- `pip3 list --outdated` + upgrade each
- Bypasses PEP 668 with `--break-system-packages`
- Skips upgrading `pip` itself

### `update_pi_apps.sh`
- `updater cli-yes` (non-interactive)
- Must run as local user (not root)

### `docker_cleanup.sh`
- `docker system prune -f --volumes`
- Auto-detects `buildx` vs legacy `builder prune`
