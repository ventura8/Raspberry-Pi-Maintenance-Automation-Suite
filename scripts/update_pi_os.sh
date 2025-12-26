#!/bin/bash
# Description: Performs a system-wide update of Raspberry Pi OS using apt-get.
# It updates the package cache, upgrades installed software, and removes 
# unnecessary dependencies. If the update requires a restart, it logs the 
# requirement and reboots the system after sending the email report.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
# ---------------------

# Prevent ANSI color codes from being generated
export TERM=dumb
export NO_COLOR=1

LOG_FILE=$(mktemp)
PI_HOSTNAME=$(hostname)
SUBJECT_LINE="Raspberry Pi OS Update Report for $PI_HOSTNAME - $(date)"

{
    # Hardcoded separators matching text length
    echo "===================================================="
    echo "   SYSTEM OS UPDATE LOG - $(date)"
    echo "===================================================="
    echo ""

    echo "--- Running 'sudo apt-get update' ---"
    sudo apt-get update 2>&1
    echo ""

    echo "--- Running 'sudo apt-get upgrade -y' ---"
    sudo apt-get upgrade -y 2>&1
    echo ""

    echo "--- Running 'sudo apt-get autoremove -y' ---"
    sudo apt-get autoremove -y 2>&1
    echo ""

    if [ -f /var/run/reboot-required ]; then
        echo "--- REBOOT STATUS ---"
        echo "A reboot is required to finish applying updates."
        echo "The system will reboot shortly after this report is sent."
        REBOOT_NEEDED=true
    else
        echo "--- REBOOT STATUS ---"
        echo "No reboot is required at this time."
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
From: "Raspberry Pi OS Update" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$LOG_FILE")
EOF

# --- Final Action ---
if [ "$REBOOT_NEEDED" = true ]; then
    rm "$LOG_FILE"
    # Delay reboot slightly to ensure ssmtp process completes
    sudo shutdown -r +1 "System update requires a reboot. Rebooting in 1 minute."
else
    rm "$LOG_FILE"
fi
