#!/bin/bash
# Description: Checks for and applies bootloader (EEPROM) firmware updates
# for Raspberry Pi 4/5. It runs the update automatically and schedules
# a reboot if the firmware requires it to take effect.

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

# --- Dependency Management ---
check_and_install_dependencies() {
    _pi_echo "--- Checking Dependencies ---"
    local MISSING_LOGICAL=()

    local IS_PI=false
    if grep -q "Raspberry Pi" /proc/device-tree/model 2> /dev/null || grep -q "Raspberry Pi" /proc/cpuinfo 2> /dev/null; then
        IS_PI=true
    fi

    if [ "$IS_PI" = true ]; then
        if ! command -v rpi-eeprom-update > /dev/null 2>&1; then
            MISSING_LOGICAL+=("rpi-eeprom")
        fi
    else
        if ! command -v fwupdmgr > /dev/null 2>&1; then
            MISSING_LOGICAL+=("fwupd")
        fi
    fi

    if ! has_mail_sender; then
        MISSING_LOGICAL+=("mail-transport")
    fi

    if [ ${#MISSING_LOGICAL[@]} -gt 0 ]; then
        echo "Installing missing dependencies: ${MISSING_LOGICAL[*]}"
        if pkg_install "${MISSING_LOGICAL[@]}"; then
            _pi_echo "Dependencies installed successfully."
        else
            _pi_echo "Warning: Some dependencies may have failed to install."
        fi
    else
        _pi_echo "All dependencies are installed."
    fi
    echo ""
}

main() {
    LOG_FILE=$(mktemp)
    PI_HOSTNAME=$(hostname)
    SUBJECT_LINE="Raspberry Pi Firmware Update Report for $PI_HOSTNAME - $(date)"

    {
        # Hardcoded separators matching text length
        _pi_echo "======================================================="
        echo "   PI FIRMWARE UPDATE LOG - $(date)"
        _pi_echo "======================================================="
        echo ""

        # Ensure dependencies are present
        check_and_install_dependencies

        if command -v rpi-eeprom-update > /dev/null 2>&1; then
            _pi_echo "--- Running 'sudo rpi-eeprom-update -a' ---"
            # The -a flag applies updates automatically if available
            UPDATE_OUTPUT=$(sudo rpi-eeprom-update -a 2>&1)
            echo "$UPDATE_OUTPUT"
            echo ""

            # Check if the output indicates an update was successful or a reboot is required
            if echo "$UPDATE_OUTPUT" | grep -qiE "reboot|UPDATE SUCCESSFUL"; then
                REBOOT_NEEDED=true
            else
                REBOOT_NEEDED=false
            fi

        elif command -v fwupdmgr > /dev/null 2>&1; then
            _pi_echo "--- Running 'fwupdmgr' ---"
            # Refresh metadata
            _pi_echo "Refreshing metadata..."
            sudo fwupdmgr refresh --force 2>&1

            # Newer fwupd uses get-upgrades; keep get-updates as compatibility fallback.
            _pi_echo "Checking for updates..."
            FWUPD_LIST_OUTPUT=""
            FWUPD_CHECK_OK=false
            if FWUPD_LIST_OUTPUT=$(sudo fwupdmgr get-upgrades 2>&1); then
                FWUPD_CHECK_OK=true
            elif FWUPD_LIST_OUTPUT=$(sudo fwupdmgr get-updates 2>&1); then
                FWUPD_CHECK_OK=true
            fi

            echo "$FWUPD_LIST_OUTPUT"

            FWUPD_NO_UPDATE_REGEX="No upgrades|No updates|No updatable devices|Devices with no available firmware updates"
            if [ "$FWUPD_CHECK_OK" = true ] &&
                ! echo "$FWUPD_LIST_OUTPUT" | grep -qiE "$FWUPD_NO_UPDATE_REGEX"; then
                _pi_echo "Updates available. Installing..."
                UPDATE_OUTPUT=$(sudo fwupdmgr update -y --no-reboot 2>&1)
                echo "$UPDATE_OUTPUT"

                # Check for reboot requirement in fwupd output
                # fwupd usually prompts or states "Restart now?" or "Scheduled"
                # For safety, if we updated something, we might assume reboot if unsure,
                # but "Successfully installed" usually appears.
                # We'll look for keywords indicating success and need for restart.
                if echo "$UPDATE_OUTPUT" | grep -qiE "Restarting|Must be restarted|Reboot required|Successfully installed"; then
                    REBOOT_NEEDED=true
                else
                    REBOOT_NEEDED=false
                fi
            elif [ "$FWUPD_CHECK_OK" = false ]; then
                _pi_echo "fwupdmgr failed to query update availability. Skipping firmware apply step."
                REBOOT_NEEDED=false
            else
                _pi_echo "No updates available."
                REBOOT_NEEDED=false
            fi
            echo ""
        else
            _pi_echo "No supported firmware update tool found (rpi-eeprom-update or fwupdmgr)."
            REBOOT_NEEDED=false
        fi

        if [ "$REBOOT_NEEDED" = true ]; then
            _pi_echo "--- REBOOT STATUS ---"
            _pi_echo "A firmware update was applied. A reboot is required."
            _pi_echo "The system will reboot shortly after this report is sent."
        else
            _pi_echo "--- REBOOT STATUS ---"
            _pi_echo "No firmware update was applied or no reboot is required."
        fi

        _pi_echo "======================================================="
        echo "   Maintenance Finished at $(date)"
        _pi_echo "======================================================="
    } > "$LOG_FILE"

    if ! declare -F send_mail > /dev/null 2>&1; then
        echo "ERROR: mail helper (lib/mail_send.sh) is not available" >&2
        return 1
    fi
    if ! send_mail "$RECIPIENT_EMAIL" "$SUBJECT_LINE" "Raspberry Pi Firmware" "$LOG_FILE"; then
        echo "WARNING: failed to deliver email notification" >&2
    fi
    # --- Final Action ---
    if [ "$REBOOT_NEEDED" = true ]; then
        rm "$LOG_FILE"
        sudo shutdown -r +1 "Firmware update requires a reboot. Rebooting in 1 minute."
    else
        rm "$LOG_FILE"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
