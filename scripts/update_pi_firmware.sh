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

LOG_FILE=$(mktemp)
PI_HOSTNAME=$(hostname)
SUBJECT_LINE="Raspberry Pi Firmware Update Report for $PI_HOSTNAME - $(date)"

{
    # Hardcoded separators matching text length
    echo "======================================================="
    echo "   PI FIRMWARE UPDATE LOG - $(date)"
    echo "======================================================="
    echo ""

    echo "--- Running 'sudo rpi-eeprom-update -a' ---"
    # The -a flag applies updates automatically if available
    UPDATE_OUTPUT=$(sudo rpi-eeprom-update -a 2>&1)
    echo "$UPDATE_OUTPUT"
    echo ""

    # Check if the output indicates an update was successful or a reboot is required
    if echo "$UPDATE_OUTPUT" | grep -qiE "reboot|UPDATE SUCCESSFUL"; then
        echo "--- REBOOT STATUS ---"
        echo "A firmware update was applied. A reboot is required."
        echo "The system will reboot shortly after this report is sent."
        REBOOT_NEEDED=true
    else
        echo "--- REBOOT STATUS ---"
        echo "No firmware update was applied or no reboot is required."
        REBOOT_NEEDED=false
    fi
    echo ""

    echo "======================================================="
    echo "   Maintenance Finished at $(date)"
    echo "======================================================="
} > "$LOG_FILE"

# --- Send the report ---
/usr/sbin/ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Raspberry Pi Firmware" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$LOG_FILE")
EOF

# --- Final Action ---
if [ "$REBOOT_NEEDED" = true ]; then
    rm "$LOG_FILE"
    sudo shutdown -r +1 "Firmware update requires a reboot. Rebooting in 1 minute."
else
    rm "$LOG_FILE"
fi
