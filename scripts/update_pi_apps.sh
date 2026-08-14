#!/bin/bash
# Description: Automates the update process for the Pi-Apps manager and all applications
# installed through it. It runs silently in CLI mode and aggressively cleans
# ANSI color codes and window title sequences to ensure readable emails.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
# ---------------------

_RPI_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_RPI_HERE/lib/os_pkg.sh" ]; then
    # shellcheck source=../lib/os_pkg.sh
    source "$_RPI_HERE/lib/os_pkg.sh"
    # shellcheck source=../lib/mail_send.sh
    source "$_RPI_HERE/lib/mail_send.sh"
    # shellcheck source=../lib/i18n.sh
    source "$_RPI_HERE/lib/i18n.sh"
elif [ -f "$_RPI_HERE/../lib/os_pkg.sh" ]; then
    # shellcheck source=../lib/os_pkg.sh
    source "$_RPI_HERE/../lib/os_pkg.sh"
    # shellcheck source=../lib/mail_send.sh
    source "$_RPI_HERE/../lib/mail_send.sh"
    # shellcheck source=../lib/i18n.sh
    source "$_RPI_HERE/../lib/i18n.sh"
fi

main() {
    LOG_FILE=$(mktemp)
    PI_HOSTNAME=$(hostname)
    SUBJECT_LINE="Raspberry Pi (Pi-Apps) Update Report for $PI_HOSTNAME - $(date)"

    {
        # Hardcoded separators matching text length
        _pi_echo "===================================================="
        echo "   PI-APPS UPDATE LOG - $(date)"
        _pi_echo "===================================================="
        echo ""

        _pi_echo "--- Updating Pi-Apps and Installed Apps ---"

        UPDATER_PATH="$HOME/pi-apps/updater"

        if [ -f "$UPDATER_PATH" ]; then
            # We use 'cli-yes' which performs a full update.
            # We pipe through sed to strip:
            # 1. ANSI color codes (e.g., [96m)
            # 2. Window Title sequences (e.g., ]0;...BEL)
            # 3. Carriage returns to fix line wrapping
            "$UPDATER_PATH" cli-yes 2>&1 |
                sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' |
                sed -r 's/\x1B\]0;[^\x07]*\x07//g'
        else
            echo "Pi-Apps updater not found at $UPDATER_PATH"
            _pi_echo "Skipping update (not installed or wrong path)."
        fi

        echo ""

        _pi_echo "======================================================="
        echo "   Maintenance Finished at $(date)"
        _pi_echo "======================================================="
    } > "$LOG_FILE"

    if ! declare -F send_mail > /dev/null 2>&1; then
        echo "ERROR: mail helper (lib/mail_send.sh) is not available" >&2
        return 1
    fi
    if ! send_mail "$RECIPIENT_EMAIL" "$SUBJECT_LINE" "Raspberry Pi Maintenance" "$LOG_FILE"; then
        echo "WARNING: failed to deliver email notification" >&2
    fi
    # --- Cleanup ---
    rm "$LOG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
