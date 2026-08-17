______________________________________________________________________

## applyTo: "\*\*/\*.sh" description: "Bash coding rules for installers, maintenance scripts, and lib helpers."

# Shell Script Instructions

1. Prefer explicit, testable Bash; quote expansions; fail closed on unexpected states.
1. Line length ≤ 140. No `# shellcheck disable` / lint suppressions.
1. Do not add interactive prompts to cron/automated paths — especially `install.sh --update`.
1. Use `lib/os_pkg.sh` for multi-family package installs (`apt` / `dnf` / `pacman`).
1. Use `lib/mail_send.sh` for notification sends when available.
1. Use `lib/ui_msg.sh` for user-facing strings (`_pi_gettext` / `_pi_gettextf` / `_pi_echo` / `_pi_echof`). These are English-only helpers — do not add gettext catalogs or PO tooling.
1. Preserve Pi vs non-Pi behavior: skip Pi-only tasks on non-Pi; keep firmware updates available.
1. Samsung path: LVFS stable first; never enable testing channels.
1. Self-update stages tagged `install.sh` + `VERSION` + `lib/` in a `mktemp` directory, exports `RAW_URL` for that tag, and invokes `bash "$stage_dir/install.sh" --update` with no stdin piping (never `$INSTALL_DIR/../install.sh`).
1. `download_scripts` must replace files atomically (`mktemp` + `mv`). Suite crontab lines use `>/dev/null 2>&1`.
1. Shipped maintenance scripts must set `RECIPIENT_EMAIL="your_email@gmail.com"`. `download_scripts` must rewrite `RECIPIENT_EMAIL="..."` to the configured mail user (do not rely on replacing the literal placeholder string alone).
1. Installer UI: whiptail default; text UI automatic fallback only when whiptail cannot run.
1. Keep public function names stable when tests source `install.sh`.
