#!/bin/bash
# Description: One-line uninstaller for the Raspberry Pi Maintenance Suite.
# Removes all scheduled cron jobs and deletes the installation directory.

main() {
    INSTALL_DIR="${INSTALL_DIR:-$HOME/pi-scripts}"

    echo "============================================"
    echo "   RPi Maintenance Suite Uninstaller"
    echo "============================================"

    # 1. Remove Crontab entries
    echo "Cleaning up crontabs..."

    sudo crontab -l 2>/dev/null | tr -d '\r' > /tmp/root_cron.bak || true
    if [ -s /tmp/root_cron.bak ]; then
        grep -v "update_pi_os.sh" < /tmp/root_cron.bak \
            | grep -v "update_pip.sh" \
            | grep -v "update_pi_firmware.sh" \
            | grep -v "docker_cleanup.sh" \
            | grep -v "update_samsung_ssd.sh" \
            | grep -v "update_self.sh" \
            > /tmp/root_cron.new
        
        # Check if the new crontab is different from the old one
        if ! diff -q /tmp/root_cron.bak /tmp/root_cron.new >/dev/null; then
            sudo crontab /tmp/root_cron.new
            echo "Root crontab updated."
        fi
        rm -f /tmp/root_cron.bak /tmp/root_cron.new
    fi

    # Remove from User Crontab
    crontab -l 2>/dev/null | tr -d '\r' > /tmp/user_cron.bak || true
    if [ -s /tmp/user_cron.bak ]; then
        grep -v 'update_pi_apps.sh' < /tmp/user_cron.bak > /tmp/user_cron.new
        crontab /tmp/user_cron.new
        rm -f /tmp/user_cron.bak /tmp/user_cron.new
    fi

    # 2. Remove Files
    # Try to detect INSTALL_DIR from crontab if it doesn't exist
    # Try to detect INSTALL_DIR from crontab if it doesn't exist or is the default
    if [ ! -d "$INSTALL_DIR" ] || [ "$INSTALL_DIR" == "$HOME/pi-scripts" ]; then
        # Check root crontab
        local detected; detected=$(sudo crontab -l 2>/dev/null | grep "update_pi_os.sh" | awk '{print $NF}' | sed 's/\/update_pi_os.sh//')
        # If not in root, check user crontab
        if [ -z "$detected" ]; then
            detected=$(crontab -l 2>/dev/null | grep "update_pi_apps.sh" | awk '{print $NF}' | sed 's/\/update_pi_apps.sh//')
        fi
        
        if [ -n "$detected" ] && [ -d "$detected" ]; then
            INSTALL_DIR="$detected"
            echo "Detected installation directory: $INSTALL_DIR"
        fi
    fi

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

# --- Entry Point ---
# Check if we are running as a script (not sourced)
# If BASH_SOURCE is empty (piped) or matches $0, we assume it's the main script.
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Helper to run interactive function with tty
    run_interactive() {
        if [ "${TEST_MODE:-false}" = "true" ]; then
             "$@"
             return
        fi

        if [ -t 0 ]; then
            "$@"
        elif [ -c /dev/tty ]; then
            # If stdin is not a terminal (e.g. piped from curl), try to use /dev/tty
            "$@" < /dev/tty
        else
            # Allow non-interactive mode (e.g. automation)
            "$@"
        fi
    }

    run_interactive main "$@"
fi
