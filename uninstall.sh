#!/bin/bash
# Description: One-line uninstaller for the Raspberry Pi Maintenance Suite.
# Removes all scheduled cron jobs and deletes the installation directory.

_RPI_UNINSTALL_ROOT="${PI_UNINSTALL_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DEFAULT_INSTALL_DIR="/usr/local/lib/pi-maintenance"
# Pre-v1.1.5 installs lived in a user-writable $HOME/pi-scripts; still cleaned up here.
LEGACY_INSTALL_DIR="${LEGACY_INSTALL_DIR:-$HOME/pi-scripts}"

if [[ -f "$_RPI_UNINSTALL_ROOT/lib/ui_msg.sh" ]]; then
    # shellcheck source=lib/ui_msg.sh
    source "$_RPI_UNINSTALL_ROOT/lib/ui_msg.sh"
elif [[ -f "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}/lib/ui_msg.sh" ]]; then
    # shellcheck source=lib/ui_msg.sh
    source "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}/lib/ui_msg.sh"
elif ! declare -F _pi_echo > /dev/null 2>&1; then
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
                *) ;;
            esac
        done
        printf '%s' "$format"
        return
    }
    _pi_echo() { printf '%s\n' "$1"; }
    _pi_echof() {
        local format
        format=$(_pi_gettextf "$@")
        printf '%s\n' "$format"
        return
    }
fi

# Directory of the first suite script referenced in a crontab dump ($1 = file), or nothing.
_cron_script_dir() {
    local cron_dump="$1"
    local names='update_pi_os|update_pi_firmware|update_pip|update_pi_apps|docker_cleanup|update_samsung_ssd|update_self'
    sed -nE "s#^.* (/[^ ]*)/($names)\\.sh.*\$#\\1#p" "$cron_dump" 2> /dev/null | head -n 1
    return
}

# Only delete a directory that carries the installer's .version marker and whose every entry is
# something the installer created —
# a hand-written crontab line such as /home/pi/update_pi_os.sh must never remove a home directory.
# Names the installer creates inside lib/.
_is_suite_lib_name() {
    case "$1" in
        os_pkg.sh | mail_send.sh | ui_msg.sh | .rpi-install.* | *.rpi-new.*) return 0 ;;
        *) ;;
    esac
    return 1
}

# Names the installer creates at the top of an install tree (lib/ is checked separately).
_is_suite_entry_name() {
    case "$1" in
        .version | .rpi-install.* | *.rpi-new.*) return 0 ;;
        update_pi_os.sh | update_pi_firmware.sh | update_pip.sh | update_pi_apps.sh) return 0 ;;
        docker_cleanup.sh | update_samsung_ssd.sh | update_self.sh) return 0 ;;
        *) ;;
    esac
    return 1
}

_lib_is_suite_only() {
    local dir="$1" entry
    [[ -d "$dir" ]] || return 1
    for entry in "$dir"/* "$dir"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        _is_suite_lib_name "${entry##*/}" || return 1
    done
    return 0
}

_dir_is_suite_only() {
    local dir="$1" entry
    # The installer always writes .version; a directory without that marker is not ours to delete.
    [[ -f "$dir/.version" ]] || return 1
    for entry in "$dir"/* "$dir"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        if [[ "${entry##*/}" = "lib" ]]; then
            _lib_is_suite_only "$entry" || return 1
        else
            _is_suite_entry_name "${entry##*/}" || return 1
        fi
    done
    return 0
}

# Remove an install tree; the default location is root-owned, so escalate when we cannot write it.
_remove_install_tree() {
    local dir="$1"
    if [[ -w "$dir" ]] && [[ -w "$(dirname "$dir")" ]]; then
        rm -rf "$dir"
    else
        sudo rm -rf "$dir"
    fi
    return
}

main() {
    INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

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
    # Remember where root cron pointed before the entries are stripped below.
    local detected
    detected=$(_cron_script_dir "$root_cron_bak")
    if [[ -s "$root_cron_bak" ]]; then
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
    [[ -n "$detected" ]] || detected=$(_cron_script_dir "$user_cron_bak")
    if [[ -s "$user_cron_bak" ]]; then
        grep -v 'update_pi_apps.sh' < "$user_cron_bak" | grep -v "^MAILTO=" > "$user_cron_new"
        crontab "$user_cron_new"
    fi
    rm -f "$user_cron_bak" "$user_cron_new"

    # 2. Remove Files
    # Prefer the directory the crontabs pointed at when INSTALL_DIR is missing or just the default.
    if { [[ ! -d "$INSTALL_DIR" ]] || [[ "$INSTALL_DIR" == "$DEFAULT_INSTALL_DIR" ]]; } &&
        [[ -n "$detected" ]] && [[ -d "$detected" ]] &&
        [[ "$detected" != "$INSTALL_DIR" ]]; then
        INSTALL_DIR="$detected"
        echo "Detected installation directory: $INSTALL_DIR"
    fi

    if [[ -d "$INSTALL_DIR" ]] && ! _dir_is_suite_only "$INSTALL_DIR"; then
        echo "Refusing to remove $INSTALL_DIR: it contains files the installer did not create."
    elif [[ -d "$INSTALL_DIR" ]]; then
        echo "Removing scripts from $INSTALL_DIR..."
        _remove_install_tree "$INSTALL_DIR"
    else
        echo "Installation directory $INSTALL_DIR not found. Skipping removal."
    fi

    # Legacy user-writable tree from older releases
    if [[ "$LEGACY_INSTALL_DIR" != "$INSTALL_DIR" ]] && [[ -d "$LEGACY_INSTALL_DIR" ]]; then
        if _dir_is_suite_only "$LEGACY_INSTALL_DIR"; then
            echo "Removing legacy scripts from $LEGACY_INSTALL_DIR..."
            _remove_install_tree "$LEGACY_INSTALL_DIR"
        else
            echo "Refusing to remove legacy $LEGACY_INSTALL_DIR: it contains files the installer did not create."
        fi
    fi

    _pi_echo "--------------------------------------------"
    _pi_echo "Uninstallation complete."
    _pi_echo "Note: Mail transport packages (ssmtp/mailutils or msmtp/s-nail) were left installed as system packages."
    _pi_echo "Mailer configuration files under /etc/ssmtp/ or /etc/msmtprc were not removed to preserve backups."
    _pi_echo "============================================"
    return
}

run_interactive() {
    if [[ "${TEST_MODE:-false}" = "true" ]]; then
        "$@"
        return
    fi

    if [[ -t 0 ]]; then
        "$@"
    elif [[ "${TEST_MODE:-false}" != "true" ]] && [[ -c /dev/tty ]] && { true < /dev/tty; } 2> /dev/null; then
        # If stdin is not a terminal (e.g. piped from curl), try to use /dev/tty
        "$@" < /dev/tty
    else
        # Allow non-interactive mode (e.g. automation)
        "$@"
    fi
    return
}

# --- Entry Point ---
# Check if we are running as a script (not sourced)
# If BASH_SOURCE is empty (piped) or matches $0, we assume it's the main script.
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

    run_interactive main "$@"
fi
