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
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

main() {
    LOG_FILE=$(mktemp)
    PI_HOSTNAME=$(hostname)
    SUBJECT_LINE="Raspberry Pi Pip Update Report for $PI_HOSTNAME - $(date)"

    {
        # Hardcoded separators matching text length
        echo "===================================================="
        echo "   PIP PACKAGE UPDATE LOG - $(date)"
        echo "===================================================="
        echo ""

        echo "--- Skipping pip3 self-upgrade ---"
        echo "Base pip3 is managed by the OS (Debian) to avoid record-file errors."
        echo ""

        echo "--- Upgrading outdated pip3 packages ---"
        # Extract package names while ignoring the header and any warning noise
        OUTDATED_PACKAGES=$(sudo -H pip3 list --outdated --break-system-packages 2>/dev/null | awk 'NR>2 {print $1}')

        if [ -z "$OUTDATED_PACKAGES" ]; then
            echo "All pip3 packages are up-to-date."
        else
            echo "Upgrading: $OUTDATED_PACKAGES"
            # Filter warnings during the bulk upgrade process
            echo "$OUTDATED_PACKAGES" | xargs sudo -H pip3 install --upgrade --break-system-packages 2>&1 | grep -vE "DEPRECATION|Wheel filename|normalized"
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
From: "Raspberry Pi Pip Update" <$RECIPIENT_EMAIL>
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
