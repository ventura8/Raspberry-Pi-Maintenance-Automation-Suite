# Script Logic & Functionality

Each script: executes commands → captures logs → sends email → handles reboots.

______________________________________________________________________

## Scripts

### `update_pi_os.sh`

- `apt-get update` + `full-upgrade` + `autoremove`
- Uses `DEBIAN_FRONTEND=noninteractive`
- Checks `/var/run/reboot-required`
- Ships `RECIPIENT_EMAIL="your_email@gmail.com"`; the installer rewrites that assignment to the user's configured address on download/`--update`

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

- Compares local `.version` (copy of repo [`VERSION`](../VERSION) written at install time) against latest GitHub release tag via the Releases API
- On update available: stages tagged `install.sh`, `VERSION`, and `lib/` in a `mktemp` directory (fails closed if staging dir or tag/`VERSION` mismatch), exports `RAW_URL` for that tag, then runs `bash "$stage_dir/install.sh" --update` (non-interactive; safe in cron — no `/dev/tty` access)
- `--update` sources package/mail helpers from `$INSTALL_DIR/lib` when the installer tree has no sibling `lib/` (so a parent-dir copy of `install.sh` still works)
- `download_scripts` writes scripts via `mktemp` under the destination directory + `mv` so a running `update_self.sh` is not truncated and replace stays same-filesystem
- `--update` rewrites existing suite crontab lines to `>/dev/null 2>&1` (preserving `@daily`-style macros) so cron MAILTO does not dump logs
- On success: writes the new release tag to `.version`; sends success email
- On any failure: sends failure email via `ssmtp`
- **Cron safety**: installer is invoked directly with no stdin pipe — piping caused `No such device or address` on `/dev/tty` in cron environments

### `install.sh`

- **Default UI**: whiptail dialogs (checklist / menu / inputbox / passwordbox / yesno / msgbox) for fresh install and manager menu
- **Cancel**: fresh wizard exposes Continue/Cancel and Download/Cancel buttons; Esc on email/checklist aborts with an "Installation cancelled…" message (does not fall back to text UI)
- **Fallback UI**: classic text prompts when whiptail is missing, fails to install, or cannot run (automatic — no `--legacy` flag)
- **Dependencies**: installs `curl`, `ssmtp`/`mailutils` (or `msmtp` fallback), and `whiptail` via `check_dependencies`
- **Version**: `download_scripts` writes `$INSTALL_DIR/.version` from the repo-root `VERSION` file (local tree first, else `$RAW_URL/VERSION`); remote fetches use `curl -fsSL` (fail on HTTP errors)
- **Version display**: interactive UI shows `read_suite_version` in the text header, whiptail welcome, and main menu from the start
- **`--update`**: non-interactive path used by `update_self.sh` (dependency check + script download + quiet existing cron redirects; fail closed if package helpers are not loaded)
- **Email injection**: shipped maintenance scripts use `RECIPIENT_EMAIL="your_email@gmail.com"`; `download_scripts` rewrites `RECIPIENT_EMAIL="..."` to the configured ssmtp/msmtp user (not a literal `your_email@gmail.com` string replace), matching `save_email_configuration`
- **`INSTALL_MATRIX_FRESH=1`**: deterministic CI/matrix fresh install (`MATRIX_EMAIL` / `MATRIX_PASS`) without stdin blank-line protocol or manager menu
- Single-file installer for `curl|bash`: when no adjacent or installed `lib/` is present, bootstraps `os_pkg.sh` / `mail_send.sh` / `ui_msg.sh` from `$RAW_URL/lib/` into a temp dir before `check_dependencies` so `pkg_install` / `has_mail_sender` exist; uses `/dev/tty` when stdin is piped; shared `lib/` is still copied/fetched into `$INSTALL_DIR/lib` for maintenance scripts
