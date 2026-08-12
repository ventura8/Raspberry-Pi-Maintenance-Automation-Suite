#!/bin/bash
# Description: Performs a system-wide OS update using the native package manager
# (apt / dnf / pacman). Detects if a reboot is required and schedules it after
# sending the report.

# --- Configuration ---
RECIPIENT_EMAIL="alexandrescu.sergiu@gmail.com"
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

# Allow overriding for testing
REBOOT_REQUIRED_FILE="${REBOOT_REQUIRED_FILE:-/var/run/reboot-required}"

main() {
    LOG_FILE=$(mktemp)
    PI_HOSTNAME=$(hostname)
    SUBJECT_LINE="System OS Update Report for $PI_HOSTNAME - $(date)"

    {
        _pi_echo "===================================================="
        echo "   SYSTEM OS UPDATE LOG - $(date)"
        _pi_echo "===================================================="
        echo ""

        pkg_update_system
        echo ""

        if [ -f "$REBOOT_REQUIRED_FILE" ]; then
            _pi_echo "--- REBOOT STATUS ---"
            _pi_echo "A reboot is required to finish applying updates."
            _pi_echo "The system will reboot shortly after this report is sent."
            REBOOT_NEEDED=true
        else
            _pi_echo "--- REBOOT STATUS ---"
            _pi_echo "No reboot is required at this time."
            REBOOT_NEEDED=false
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
    if ! send_mail "$RECIPIENT_EMAIL" "$SUBJECT_LINE" "System OS Update" "$LOG_FILE"; then
        echo "WARNING: failed to deliver email notification" >&2
    fi
    if [ "$REBOOT_NEEDED" = true ]; then
        rm "$LOG_FILE"
        sudo shutdown -r +1 "System update requires a reboot. Rebooting in 1 minute."
    else
        rm "$LOG_FILE"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
