______________________________________________________________________

## description: "Validate install.sh whiptail UI, text fallback, and --update. Optional focus: {{FOCUS}}."

# Installer Test: {{FOCUS}}

Follow `.agents/skills/installer-tester`.

Run installer BATS (including whiptail + fallback). Cover piped `curl|bash` with a TTY so
prompts read from `/dev/tty` (not the installer pipe). Cover missing whiptail and failed
whiptail install (both must fall back to text UI); User Cancel must not force text fallback.
Confirm `--update` stays non-interactive.

Deliver: scenarios covered and results.
