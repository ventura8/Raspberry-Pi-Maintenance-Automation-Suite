#!/bin/bash
# Description: One-line uninstaller for the Raspberry Pi Maintenance Suite.
# Removes all scheduled cron jobs and deletes the installation directory.

main() {
    INSTALL_DIR="$HOME/pi-scripts"

    echo "============================================"
    echo "   RPi Maintenance Suite Uninstaller"
    echo "============================================"

    # 1. Remove Crontab entries
    echo "Cleaning up crontabs..."

    # Remove from Root Crontab
    # We use grep -vE to filter out any lines containing our specific script names.
    # This works regardless of the specific time schedule set by the user.
    sudo crontab -l 2>/dev/null | grep -vE "update_pi_os.sh|update_pip.sh|update_pi_firmware.sh|docker_cleanup.sh" | sudo crontab -

    # Remove from User Crontab
    crontab -l 2>/dev/null | grep -vE "update_pi_apps.sh" | crontab -

    # 2. Remove Files
    if [ -d "$INSTALL_DIR" ]; then
        echo "Removing scripts from $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"
    else
        echo "Installation directory $INSTALL_DIR not found. Skipping removal."
    fi

    echo "--------------------------------------------"
    echo "Uninstallation complete."
    echo "Note: SSMTP and mailutils were left installed as they are system packages."
    echo "Configuration files at /etc/ssmtp/ were not removed to preserve backups."
    echo "============================================"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
