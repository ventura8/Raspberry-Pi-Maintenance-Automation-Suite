#!/bin/bash
# Description: Automates the update process for the Pi-Apps manager and all applications 
# installed through it. It runs silently in CLI mode and aggressively cleans 
# ANSI color codes and window title sequences to ensure readable emails.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
# ---------------------
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

main() {
    LOG_FILE=$(mktemp)
    PI_HOSTNAME=$(hostname)
    SUBJECT_LINE="Raspberry Pi (Pi-Apps) Update Report for $PI_HOSTNAME - $(date)"

    {
        # Hardcoded separators matching text length
        echo "===================================================="
        echo "   PI-APPS UPDATE LOG - $(date)"
        echo "===================================================="
        echo ""

        echo "--- Updating Pi-Apps and Installed Apps ---"
        
        UPDATER_PATH="$HOME/pi-apps/updater"
        
        if [ -f "$UPDATER_PATH" ]; then
            # We use 'cli-yes' which performs a full update.
            # We pipe through sed to strip:
            # 1. ANSI color codes (e.g., [96m)
            # 2. Window Title sequences (e.g., ]0;...BEL)
            # 3. Carriage returns to fix line wrapping
            "$UPDATER_PATH" cli-yes 2>&1 | \
            sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' | \
            sed -r 's/\x1B\]0;[^\x07]*\x07//g'
        else
            echo "Pi-Apps updater not found at $UPDATER_PATH"
            echo "Skipping update (not installed or wrong path)."
        fi
        
        echo ""
        
        echo "======================================================="
        echo "   Maintenance Finished at $(date)"
        echo "======================================================="
    } > "$LOG_FILE"

    # --- Send the report ---
    if command -v ssmtp >/dev/null 2>&1; then
        ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Raspberry Pi Maintenance" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$LOG_FILE")
EOF
    else
        echo "ssmtp not found, skipping email notification."
    fi

    # --- Cleanup ---
    rm "$LOG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
