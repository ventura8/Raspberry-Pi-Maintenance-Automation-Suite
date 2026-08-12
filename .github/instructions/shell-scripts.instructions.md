______________________________________________________________________

## applyTo: "\*\*/\*.sh" description: "Bash coding rules for installers, maintenance scripts, and lib helpers."

# Shell Script Instructions

1. Prefer explicit, testable Bash; quote expansions; fail closed on unexpected states.
1. Line length ≤ 140. No `# shellcheck disable` / lint suppressions.
1. Do not add interactive prompts to cron/automated paths — especially `install.sh --update`.
1. Use `lib/os_pkg.sh` for multi-family package installs (`apt` / `dnf` / `pacman`).
1. Use `lib/mail_send.sh` for notification sends when available.
1. Use `lib/i18n.sh` for user-facing strings (`_pi_gettext` / `_pi_gettextf` / `_pi_ngettext` /
   `_pi_pgettext`). When changing marked strings, update `po/pi-maintenance-suite.pot` and every
   `po/*.po` in the same change set; run `scripts/i18n/check_catalog_quality.py`.
1. Preserve Pi vs non-Pi behavior: skip Pi-only tasks on non-Pi; keep firmware updates available.
1. Samsung path: LVFS stable first; never enable testing channels.
1. Self-update must invoke `bash install.sh --update` without stdin piping.
1. Installer UI: whiptail default; text UI automatic fallback only when whiptail cannot run.
1. Keep public function names stable when tests source `install.sh`.
