#!/bin/bash
# Description: Automates the update process for the Pi-Apps manager and all applications 
# installed through it. It runs silently in CLI mode, suppresses ANSI formatting 
# using environment variables, and sends a detailed report to a Gmail account.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
# ---------------------

# Prevent ANSI color codes and terminal title sequences from being generated
export TERM=dumb
export NO_COLOR=1

LOG_FILE=$(mktemp)
PI_HOSTNAME=$(hostname)
SUBJECT_LINE="Raspberry Pi (Pi-Apps) Update Report for $PI_HOSTNAME - $(date)"

# --- Main Script ---
{
    # Hardcoded separators matching text length spaces
    echo "===================================================="
    echo "   PI-APPS UPDATE LOG - $(date)"
    echo "===================================================="
    echo ""

    echo "--- Step 1: Updating Pi-Apps Manager ---"
    # Using 'cli-yes' for automatic non-interactive updates
    ~/pi-apps/updater cli-yes --update-self 2>&1
    echo ""

    echo "--- Step 2: Updating all apps ---"
    # Using 'cli-yes' for automatic non-interactive updates
    ~/pi-apps/updater cli-yes --update-all 2>&1
    echo ""
    
    echo "======================================================="
    echo "   Maintenance Finished at $(date)"
    echo "======================================================="
} > "$LOG_FILE"

# --- Send the report ---
/usr/sbin/ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Raspberry Pi Maintenance" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$LOG_FILE")
EOF

# --- Cleanup ---
rm "$LOG_FILE"
