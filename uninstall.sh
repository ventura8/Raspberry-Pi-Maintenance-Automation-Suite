#!/bin/bash
# Description: Removes all scripts and crontab entries created by the suite.

INSTALL_DIR="$HOME/pi-scripts"

echo "============================================"
echo "   RPi Maintenance Suite Uninstaller"
echo "============================================"

# 1. Remove Crontab entries
echo "Cleaning up crontabs..."

# Remove from Root
sudo crontab -l 2>/dev/null | grep -vE "update_pi_os.sh|update_pip.sh|update_pi_firmware.sh|docker_cleanup.sh" | sudo crontab -

# Remove from User
crontab -l 2>/dev/null | grep -vE "update_pi_apps.sh" | crontab -

# 2. Remove Files
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing scripts from $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
fi

echo "Uninstallation complete."
echo "============================================"
