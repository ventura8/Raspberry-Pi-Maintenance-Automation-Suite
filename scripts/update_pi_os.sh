#!/bin/bash
# Description: Performs a system-wide update of Raspberry Pi OS using apt-get.
# Uses full-upgrade to handle dependency changes, which is recommended for 
# Raspberry Pi kernel and firmware stability. It detects if a reboot is 
# required and schedules it after sending the report.

# --- Configuration ---
RECIPIENT_EMAIL="alexandrescu.sergiu@gmail.com"
# ---------------------

# Prevent ANSI color codes from being generated
export TERM=dumb
export NO_COLOR=1
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Allow overriding for testing
REBOOT_REQUIRED_FILE="${REBOOT_REQUIRED_FILE:-/var/run/reboot-required}"

main() {
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

        echo "--- Running 'sudo apt-get full-upgrade -y' ---"
        # full-upgrade is preferred over upgrade as it handles dependency changes
        # and ensures kernel/firmware packages are correctly managed.
        sudo apt-get full-upgrade -y 2>&1
        echo ""

        echo "--- Running 'sudo apt-get autoremove -y' ---"
        sudo apt-get autoremove -y 2>&1
        echo ""

        if [ -f "$REBOOT_REQUIRED_FILE" ]; then
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
    if command -v ssmtp >/dev/null 2>&1; then
        ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Raspberry Pi OS Update" <$RECIPIENT_EMAIL>
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
        # Delay reboot slightly to ensure ssmtp process completes
        sudo shutdown -r +1 "System update requires a reboot. Rebooting in 1 minute."
    else
        rm "$LOG_FILE"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
