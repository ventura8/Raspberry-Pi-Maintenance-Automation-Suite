#!/bin/bash
# Description: Performs a system-wide update of Raspberry Pi OS using apt-get.
# It updates the package cache, upgrades installed software, and removes 
# unnecessary dependencies, mailing a log of the results.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
# ---------------------

LOG_FILE=$(mktemp)
PI_HOSTNAME=$(hostname)
SUBJECT_LINE="Raspberry Pi OS Update Report for $PI_HOSTNAME - $(date)"

{
    echo "========================================================="
    echo "   SYSTEM OS UPDATE LOG - $(date)"
    echo "========================================================="
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

    echo "========================================================="
    echo "   Maintenance Finished at $(date)"
    echo "========================================================="
} > "$LOG_FILE"

CLEAN_LOG=$(mktemp)
sed 's/$/\r/' "$LOG_FILE" > "$CLEAN_LOG"

/usr/sbin/ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Raspberry Pi OS Update" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$CLEAN_LOG")
EOF

rm "$LOG_FILE"
rm "$CLEAN_LOG"
