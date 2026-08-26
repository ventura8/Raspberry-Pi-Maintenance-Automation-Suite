______________________________________________________________________

## name: installer-tester description: Validate install.sh whiptail wizard, text UI fallback, email/cron setup, and cron-safe --update.

# Installer Tester Skill

Use when changing `install.sh`, `uninstall.sh`, installer mocks, or installer BATS.

## Invariants

1. Whiptail is the **default** interactive UI.
1. Classic text UI is **automatic fallback** when whiptail cannot run — not a separate legacy flag.
1. `install.sh --update` = `check_dependencies` + `download_scripts` + `quiet_suite_cron_jobs`; no menus; cron-safe.
1. `download_scripts` rewrites `RECIPIENT_EMAIL="..."` to the configured ssmtp/msmtp user (maintenance scripts must ship `your_email@gmail.com` only).
1. Fresh `curl|bash` bootstraps package/mail/UI helpers from `$RAW_URL/lib/` when no local `lib/` is present.
1. `quiet_suite_cron_jobs` preserves cron macros (`@daily`, etc.) when rewriting redirects.
1. `check_dependencies` installs curl, mail-transport, and whiptail (or family equivalent).
1. Piped installs must use `/dev/tty` when available (`run_interactive` / `read_input`).
1. Non-Pi skips `update_pip.sh` but keeps firmware tasks available.
1. Public function names used by BATS must remain stable unless tests are updated in the same change.
1. User-facing strings use English-only `_pi_gettext*` helpers from `lib/ui_msg.sh` (no translation catalogs).

## What to exercise

| Path                   | How                                                                                                                                 |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Whiptail fresh install | `tests/install_whiptail.bats` + mock checklist/menu inputs                                                                          |
| Text fallback          | Force `whiptail_mode=missing`                                                                                                       |
| Email configure        | Valid/invalid email, reconfigure yes/no, msmtp-only recognition (no `SSMTP_CONF`), ssmtp-to-msmtp migration, `MSMTP_CONF` isolation |
| Task enable/schedules  | Defaults ON; custom cron edits via manager                                                                                          |
| `--update`             | No TTY prompts; used by `update_self.sh`                                                                                            |
| Pi / non-Pi            | `MOCK_IS_PI=true`                                                                                                                   |
| Uninstall              | `tests/uninstall.bats` + menu option path                                                                                           |

## Commands

```bash
./tests/run_suite.sh --installer-only
# or
bats tests/install_*.bats tests/uninstall.bats
```

Docker e2e lane (text forced for noninteractive containers):

```bash
./scripts/run_docker_matrix.sh --e2e-only --distro debian:trixie --serial
```

## Mock notes

1. Whiptail mock state files under `/tmp/mocks/` (`whiptail_mode`, `whiptail_yesno`, `whiptail_input`, `whiptail_checklist`) — see `tests/setup_mocks.sh`.
1. Isolate `INSTALL_DIR` / `SSMTP_CONF` / `REVALIASES` / `MSMTP_CONF` per test.
1. Cancel (rc 1/255) must not silently switch to text UI.
1. Fresh install Cancel (welcome Continue/Cancel, download Download/Cancel, Esc on email/checklist) must abort with an "Installation cancelled…" message and non-zero status.

## Output

List scenarios covered, UI mode used, and any regressions in `--update` or fallback behavior.
