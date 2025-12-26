#!/bin/bash
# Description: Installer for the Raspberry Pi Maintenance Suite.
# Copies scripts from the local 'scripts' folder to the installation directory,
# updates the email configuration, and sets up cron jobs.

INSTALL_DIR="$HOME/pi-scripts"
SOURCE_DIR="./scripts"

echo "============================================"
echo "   RPi Maintenance Suite Installer"
echo "============================================"

# 1. Validation
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: '$SOURCE_DIR' folder not found in the current directory."
    echo "Please run this script from the root of the repository."
    exit 1
fi

# 2. Ask for Email
read -p "Enter the Gmail address for reports: " USER_EMAIL
if [[ ! $USER_EMAIL =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "Invalid email format. Aborting."
    exit 1
fi

# 3. Check for dependencies
if ! command -v ssmtp &> /dev/null; then
    echo "ssmtp not found. Installing mail utilities..."
    sudo apt-get update && sudo apt-get install -y ssmtp mailutils
fi

# 4. Setup Installation Directory
mkdir -p "$INSTALL_DIR"
echo "Installing scripts to $INSTALL_DIR..."

# 5. Copy and Configure Scripts
for script_path in "$SOURCE_DIR"/*.sh; do
    script_name=$(basename "$script_path")
    
    echo "Configuring $script_name..."
    cp "$script_path" "$INSTALL_DIR/$script_name"
    
    # Replace the placeholder email with the user provided one
    sed -i "s/your_email@gmail.com/$USER_EMAIL/g" "$INSTALL_DIR/$script_name"
    
    # Ensure it is executable
    chmod +x "$INSTALL_DIR/$script_name"
done

# 6. Setup Crontabs
echo "Configuring Crontabs..."

# Define precise paths for the cron entries
OS_SCRIPT="$INSTALL_DIR/update_pi_os.sh"
PIP_SCRIPT="$INSTALL_DIR/update_pip.sh"
FIRMWARE_SCRIPT="$INSTALL_DIR/update_pi_firmware.sh"
DOCKER_SCRIPT="$INSTALL_DIR/docker_cleanup.sh"
APPS_SCRIPT="$INSTALL_DIR/update_pi_apps.sh"

# Root Crontab (sudo)
# Cleans existing entries for these specific scripts before adding new ones
(sudo crontab -l 2>/dev/null | grep -vE "update_pi_os.sh|update_pip.sh|update_pi_firmware.sh|docker_cleanup.sh"; 
 echo "0 2 1 * * $FIRMWARE_SCRIPT";
 echo "0 3 * * 0 $OS_SCRIPT";
 echo "0 4 * * 0 $PIP_SCRIPT";
 echo "20 4 * * 0 $DOCKER_SCRIPT") | sudo crontab -

# User Crontab
(crontab -l 2>/dev/null | grep -vE "update_pi_apps.sh"; 
 echo "0 5 * * 0 $APPS_SCRIPT") | crontab -

echo "============================================"
echo "DONE! Scripts installed and cron jobs scheduled."
echo "Please ensure /etc/ssmtp/ssmtp.conf is configured."
echo "============================================"
