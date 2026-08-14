#!/bin/bash
# Description: Updates globally installed pip3 packages. Useful for keeping
# Python tools up to date with an automated email summary.
# Note: Base pip3 is managed by the OS to prevent uninstall errors.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
# ---------------------

# Prevent ANSI color codes from being generated
export TERM=dumb
export NO_COLOR=1

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
    SUBJECT_LINE="Raspberry Pi Pip Update Report for $PI_HOSTNAME - $(date)"

    {
        # Hardcoded separators matching text length
        _pi_echo "===================================================="
        echo "   PIP PACKAGE UPDATE LOG - $(date)"
        _pi_echo "===================================================="
        echo ""

        _pi_echo "--- Skipping pip3 self-upgrade ---"
        _pi_echo "Base pip3 is managed by the OS (Debian) to avoid record-file errors."
        echo ""

        _pi_echo "--- Upgrading outdated pip3 packages ---"
        # Extract package names while ignoring the header and any warning noise
        OUTDATED_PACKAGES=$(sudo -H pip3 list --outdated --break-system-packages 2> /dev/null | awk 'NR>2 {print $1}')

        if [ -z "$OUTDATED_PACKAGES" ]; then
            _pi_echo "All pip3 packages are up-to-date."
        else
            echo "Upgrading: $OUTDATED_PACKAGES"
            # Filter warnings during the bulk upgrade process
            echo "$OUTDATED_PACKAGES" |
                xargs sudo -H pip3 install --upgrade --break-system-packages 2>&1 |
                grep -vE "DEPRECATION|Wheel filename|normalized"
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
    if ! send_mail "$RECIPIENT_EMAIL" "$SUBJECT_LINE" "Raspberry Pi Pip Update" "$LOG_FILE"; then
        echo "WARNING: failed to deliver email notification" >&2
    fi
    # --- Cleanup ---
    rm "$LOG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
