#!/bin/bash
# Description: One-line uninstaller for the Raspberry Pi Maintenance Suite.
# Removes all scheduled cron jobs and deletes the installation directory.

_RPI_UNINSTALL_ROOT="${PI_UNINSTALL_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [ "${PI_I18N_FORCE_INLINE_STUBS:-0}" != "1" ] && [ -f "$_RPI_UNINSTALL_ROOT/lib/i18n_soft.sh" ]; then
    # shellcheck source=lib/i18n_soft.sh
    source "$_RPI_UNINSTALL_ROOT/lib/i18n_soft.sh"
elif [ "${PI_I18N_FORCE_INLINE_STUBS:-0}" != "1" ] && [ -f "${INSTALL_DIR:-$HOME/pi-scripts}/lib/i18n_soft.sh" ]; then
    # shellcheck source=lib/i18n_soft.sh
    source "${INSTALL_DIR:-$HOME/pi-scripts}/lib/i18n_soft.sh"
elif ! declare -F _pi_gettext > /dev/null 2>&1; then
    _pi_gettext() { printf '%s' "$1"; }
    _pi_gettextf() {
        local format="$1" argument prefix suffix
        shift
        for argument in "$@"; do
            case "$format" in
                *%s*)
                    prefix=${format%%\%s*}
                    suffix=${format#*%s}
                    format="${prefix}${argument}${suffix}"
                    ;;
            esac
        done
        printf '%s' "$format"
    }
    _pi_echo() { printf '%s\n' "$1"; }
    _pi_echof() {
        local format
        format=$(_pi_gettextf "$@")
        printf '%s\n' "$format"
    }
fi

if [ "${PI_I18N_FORCE_INLINE_STUBS:-0}" != "1" ] && [ -f "${INSTALL_DIR:-$HOME/pi-scripts}/lib/i18n.sh" ]; then
    # shellcheck source=lib/i18n.sh
    source "${INSTALL_DIR:-$HOME/pi-scripts}/lib/i18n.sh"
elif [ "${PI_I18N_FORCE_INLINE_STUBS:-0}" != "1" ] && [ -f "$_RPI_UNINSTALL_ROOT/lib/i18n.sh" ]; then
    # shellcheck source=lib/i18n.sh
    source "$_RPI_UNINSTALL_ROOT/lib/i18n.sh"
fi

main() {
    INSTALL_DIR="${INSTALL_DIR:-$HOME/pi-scripts}"

    _pi_echo "============================================"
    _pi_echo "   RPi Maintenance Suite Uninstaller"
    _pi_echo "============================================"

    # 1. Remove Crontab entries
    _pi_echo "Cleaning up crontabs..."

    local root_cron_bak root_cron_new
    root_cron_bak=$(mktemp /tmp/root_cron.XXXXXX) || return 1
    root_cron_new=$(mktemp /tmp/root_cron.XXXXXX) || {
        rm -f "$root_cron_bak"
        return 1
    }
    chmod 600 "$root_cron_bak" "$root_cron_new"

    sudo crontab -l 2> /dev/null | tr -d '\r' > "$root_cron_bak" || true
    if [ -s "$root_cron_bak" ]; then
        grep -v "update_pi_os.sh" < "$root_cron_bak" |
            grep -v "update_pip.sh" |
            grep -v "update_pi_firmware.sh" |
            grep -v "docker_cleanup.sh" |
            grep -v "update_samsung_ssd.sh" |
            grep -v "update_self.sh" |
            grep -v "^MAILTO=" \
                > "$root_cron_new"

        # Check if the new crontab is different from the old one
        if ! cmp -s "$root_cron_bak" "$root_cron_new" 2> /dev/null; then
            sudo crontab "$root_cron_new"
            _pi_echo "Root crontab updated."
        fi
    fi
    rm -f "$root_cron_bak" "$root_cron_new"

    # Remove from User Crontab
    local user_cron_bak user_cron_new
    user_cron_bak=$(mktemp /tmp/user_cron.XXXXXX) || return 1
    user_cron_new=$(mktemp /tmp/user_cron.XXXXXX) || {
        rm -f "$user_cron_bak"
        return 1
    }
    chmod 600 "$user_cron_bak" "$user_cron_new"

    crontab -l 2> /dev/null | tr -d '\r' > "$user_cron_bak" || true
    if [ -s "$user_cron_bak" ]; then
        grep -v 'update_pi_apps.sh' < "$user_cron_bak" | grep -v "^MAILTO=" > "$user_cron_new"
        crontab "$user_cron_new"
    fi
    rm -f "$user_cron_bak" "$user_cron_new"

    # 2. Remove Files
    # Try to detect INSTALL_DIR from crontab if it doesn't exist
    # Try to detect INSTALL_DIR from crontab if it doesn't exist or is the default
    if [ ! -d "$INSTALL_DIR" ] || [ "$INSTALL_DIR" == "$HOME/pi-scripts" ]; then
        # Check root crontab
        local detected
        detected=$(sudo crontab -l 2> /dev/null | grep "update_pi_os.sh" | awk '{print $NF}' | sed 's/\/update_pi_os.sh//')
        # If not in root, check user crontab
        if [ -z "$detected" ]; then
            detected=$(crontab -l 2> /dev/null | grep "update_pi_apps.sh" | awk '{print $NF}' | sed 's/\/update_pi_apps.sh//')
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

    _pi_echo "--------------------------------------------"
    _pi_echo "Uninstallation complete."
    _pi_echo "Note: Mail transport packages (ssmtp/mailutils or msmtp/s-nail) were left installed as system packages."
    _pi_echo "Mailer configuration files under /etc/ssmtp/ or /etc/msmtprc were not removed to preserve backups."
    _pi_echo "============================================"
}

run_interactive() {
    if [ "${TEST_MODE:-false}" = "true" ]; then
        "$@"
        return
    fi

    if [ -t 0 ]; then
        "$@"
    elif [[ "${TEST_MODE:-false}" != "true" ]] && [ -c /dev/tty ] && { true < /dev/tty; } 2> /dev/null; then
        # If stdin is not a terminal (e.g. piped from curl), try to use /dev/tty
        "$@" < /dev/tty
    else
        # Allow non-interactive mode (e.g. automation)
        "$@"
    fi
}

# --- Entry Point ---
# Check if we are running as a script (not sourced)
# If BASH_SOURCE is empty (piped) or matches $0, we assume it's the main script.
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

    run_interactive main "$@"
fi
