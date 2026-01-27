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
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- Dependency Management ---
check_and_install_dependencies() {
    echo "--- Checking Dependencies ---"
    local MISSING_DEPS=()
    
    # 1. Hardware Detection
    local IS_PI=false
    if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null || grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        IS_PI=true
    fi

    # 2. Define required tools
    if [ "$IS_PI" = true ]; then
        if ! command -v rpi-eeprom-update >/dev/null 2>&1; then
            MISSING_DEPS+=("rpi-eeprom-update")
        fi
    else
        if ! command -v fwupdmgr >/dev/null 2>&1; then
            MISSING_DEPS+=("fwupd")
        fi
    fi

    if ! command -v ssmtp >/dev/null 2>&1; then
        MISSING_DEPS+=("ssmtp")
    fi

    # 3. Install if missing
    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo "Installing missing dependencies: ${MISSING_DEPS[*]}"
        sudo apt-get update >/dev/null 2>&1
        if sudo apt-get install -y "${MISSING_DEPS[@]}" >/dev/null 2>&1; then
            echo "Dependencies installed successfully."
        else
            echo "Warning: Some dependencies may have failed to install."
        fi
    else
        echo "All dependencies are installed."
    fi
    echo ""
}

main() {
    LOG_FILE=$(mktemp)
    PI_HOSTNAME=$(hostname)
    SUBJECT_LINE="Raspberry Pi Firmware Update Report for $PI_HOSTNAME - $(date)"

    {
        # Hardcoded separators matching text length
        echo "======================================================="
        echo "   PI FIRMWARE UPDATE LOG - $(date)"
        echo "======================================================="
        echo ""

        # Ensure dependencies are present
        check_and_install_dependencies

        if command -v rpi-eeprom-update >/dev/null 2>&1; then
            echo "--- Running 'sudo rpi-eeprom-update -a' ---"
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

        elif command -v fwupdmgr >/dev/null 2>&1; then
            echo "--- Running 'fwupdmgr' ---"
            # Refresh metadata
            echo "Refreshing metadata..."
            sudo fwupdmgr refresh >/dev/null 2>&1
            
            # Get updates
            echo "Checking for updates..."
            if sudo fwupdmgr get-updates >/dev/null 2>&1; then
                echo "Updates available. Installing..."
                UPDATE_OUTPUT=$(sudo fwupdmgr update -y 2>&1)
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
            else
                echo "No updates available."
                REBOOT_NEEDED=false
            fi
            echo ""
        else
             echo "No supported firmware update tool found (rpi-eeprom-update or fwupdmgr)."
             REBOOT_NEEDED=false
        fi

        if [ "$REBOOT_NEEDED" = true ]; then
            echo "--- REBOOT STATUS ---"
            echo "A firmware update was applied. A reboot is required."
            echo "The system will reboot shortly after this report is sent."
        else
            echo "--- REBOOT STATUS ---"
            echo "No firmware update was applied or no reboot is required."
        fi

        echo "======================================================="
        echo "   Maintenance Finished at $(date)"
        echo "======================================================="
    } > "$LOG_FILE"

    # --- Send the report ---
    if command -v ssmtp >/dev/null 2>&1; then
        ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Raspberry Pi Firmware" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$LOG_FILE")
EOF
    else
        echo "ssmtp not found, skipping email notification."
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
