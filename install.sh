#!/bin/bash
# Description: Interactive installer for the Raspberry Pi Maintenance Suite.
# Fetches scripts, configures email, and allows selective scheduling and timing of tasks.
# Functions as a one-line installer for fresh setups, and a management UI for existing setups.
# Default UI is whiptail; current text UI is used automatically when whiptail cannot run.

# --- Configuration ---
GITHUB_USER="ventura8"
REPO_NAME="Raspberry-Pi-Maintenance-Automation-Suite"
BRANCH="main"
RAW_URL="${RAW_URL:-https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH}"

INSTALL_DIR="${INSTALL_DIR:-$HOME/pi-scripts}"
SSMTP_CONF="${SSMTP_CONF:-/etc/ssmtp/ssmtp.conf}"
REVALIASES="${REVALIASES:-/etc/ssmtp/revaliases}"
MSMTP_CONF="${MSMTP_CONF:-/etc/msmtprc}"

_INSTALL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer libs next to this installer (repo or staged tree); else the installed copy.
_install_lib_root() {
    if [ -f "$_INSTALL_ROOT/lib/os_pkg.sh" ]; then
        printf '%s' "$_INSTALL_ROOT/lib"
        return 0
    fi
    if [ -n "${INSTALL_DIR:-}" ] && [ -f "$INSTALL_DIR/lib/os_pkg.sh" ]; then
        printf '%s' "$INSTALL_DIR/lib"
        return 0
    fi
    return 1
}

_source_lib_dir() {
    local lib_root="$1"
    [ -n "$lib_root" ] && [ -f "$lib_root/os_pkg.sh" ] || return 1
    if [ -f "$lib_root/ui_msg.sh" ]; then
        # shellcheck source=lib/ui_msg.sh
        source "$lib_root/ui_msg.sh"
    fi
    # shellcheck source=lib/os_pkg.sh
    source "$lib_root/os_pkg.sh"
    # shellcheck source=lib/mail_send.sh
    source "$lib_root/mail_send.sh"
    return 0
}

# curl|bash has no sibling lib/; fetch package/mail/UI helpers from RAW_URL into a temp dir.
_fetch_bootstrap_libs() {
    local dest lib_file tmp
    command -v curl > /dev/null 2>&1 || return 1
    dest=$(mktemp -d) || return 1
    mkdir -p "$dest/lib"
    for lib_file in os_pkg.sh mail_send.sh ui_msg.sh; do
        tmp=$(mktemp "$dest/lib/.fetch.XXXXXX") || {
            rm -rf "$dest"
            return 1
        }
        if curl -fsSL "$RAW_URL/lib/$lib_file" -o "$tmp"; then
            mv -f "$tmp" "$dest/lib/$lib_file"
        else
            rm -f "$tmp"
            if [ "$lib_file" = "os_pkg.sh" ] || [ "$lib_file" = "mail_send.sh" ]; then
                rm -rf "$dest"
                return 1
            fi
        fi
    done
    printf '%s' "$dest/lib"
    return 0
}

_source_install_libs() {
    local lib_root
    if lib_root=$(_install_lib_root); then
        _source_lib_dir "$lib_root"
        return $?
    fi
    lib_root=$(_fetch_bootstrap_libs) || return 1
    _source_lib_dir "$lib_root"
}

_ensure_install_helpers() {
    if declare -F pkg_install > /dev/null 2>&1 && declare -F has_mail_sender > /dev/null 2>&1; then
        return 0
    fi
    _pi_echo "Error: package helpers not loaded. Cannot continue update."
    return 1
}

_source_install_libs || true
if ! declare -F _pi_gettext > /dev/null 2>&1; then
    # shellcheck source=lib/ui_msg.sh
    if [ -f "$_INSTALL_ROOT/lib/ui_msg.sh" ]; then
        source "$_INSTALL_ROOT/lib/ui_msg.sh"
    else
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
fi

if ! declare -F pkg_install > /dev/null 2>&1 || ! declare -F has_mail_sender > /dev/null 2>&1; then
    _source_install_libs || true
fi

# UI mode: whiptail preferred; text fallback when unavailable.
# In TEST_MODE, text is default unless INSTALL_USE_WHIPTAIL=1 (keeps stdin-driven tests stable).
INSTALL_USE_WHIPTAIL="${INSTALL_USE_WHIPTAIL:-}"
INSTALL_FORCE_TEXT_UI="${INSTALL_FORCE_TEXT_UI:-0}"
INSTALL_UI_IN_FD="${INSTALL_UI_IN_FD:-}"
INSTALL_UI_OUT_FD="${INSTALL_UI_OUT_FD:-}"
INSTALL_UI_MODE="${INSTALL_UI_MODE:-}"

# --- Script Definitions ---
declare -A SCRIPTS
# 1-based index
SCRIPTS[1]="update_pi_os.sh"
SCRIPTS[2]="update_pi_firmware.sh"
SCRIPTS[3]="update_pip.sh"
SCRIPTS[4]="docker_cleanup.sh"
SCRIPTS[5]="update_pi_apps.sh"
SCRIPTS[6]="update_samsung_ssd.sh"
SCRIPTS[7]="update_self.sh"

declare -A NAMES
NAMES[1]="System OS Update"
NAMES[2]="Firmware Update"
NAMES[3]="Python Pip Update"
NAMES[4]="Docker Cleanup"
NAMES[5]="Pi-Apps Update"
NAMES[6]="Samsung SSD Firmware Update"
NAMES[7]="Self-Update Service"

# Display name for task id.
_pi_task_name() {
    case "$1" in
        1) _pi_gettext "System OS Update" ;;
        2) _pi_gettext "Firmware Update" ;;
        3) _pi_gettext "Python Pip Update" ;;
        4) _pi_gettext "Docker Cleanup" ;;
        5) _pi_gettext "Pi-Apps Update" ;;
        6) _pi_gettext "Samsung SSD Firmware Update" ;;
        7) _pi_gettext "Self-Update Service" ;;
        *) _pi_gettext "${NAMES[$1]:-Unknown task}" ;;
    esac
}

# --- Hardware/OS Detection ---
IS_PI=false
if [ "$TEST_MODE" == "true" ] && [ -n "$MOCK_IS_PI" ]; then
    IS_PI="$MOCK_IS_PI"
elif grep -q "Raspberry Pi" /proc/device-tree/model 2> /dev/null; then
    IS_PI=true
# KCOV_EXCL_START
elif grep -q "Raspberry Pi" /proc/cpuinfo 2> /dev/null; then
    IS_PI=true
# KCOV_EXCL_STOP
fi

# Default Schedules
declare -A DEFAULTS
DEFAULTS[1]="0 3 * * 0"
DEFAULTS[2]="0 2 * * 0"
DEFAULTS[3]="0 4 * * 0"
DEFAULTS[4]="20 4 * * 0"
DEFAULTS[5]="0 5 * * 0"
DEFAULTS[6]="30 4 * * 0"
DEFAULTS[7]="0 1 * * 0" # Weekly

# --- Helper Functions ---

read_input() {
    local prompt="$1"
    local var_name="$2"
    local is_secret="$3"

    local user_val=""
    local status=0
    # If piped (curl | bash) AND not in test mode, use /dev/tty for prompt AND input
    # KCOV_EXCL_START
    if [ ! -t 0 ] && [ -c /dev/tty ] && [ "${TEST_MODE}" != "true" ]; then
        printf "%s" "$prompt" > /dev/tty
        if [[ "$is_secret" == "true" ]]; then
            read -r -s user_val < /dev/tty
        else
            read -r user_val < /dev/tty
        fi
        status=$?
        if [[ "$is_secret" == "true" ]]; then
            echo "" > /dev/tty
        fi
    else
        # KCOV_EXCL_STOP
        # Standard interactive or automated/test mode
        printf "%s" "$prompt" >&2
        if [[ "$is_secret" == "true" ]]; then
            read -r -s user_val
        else
            read -r user_val
        fi
        status=$?
        if [[ "$is_secret" == "true" ]]; then
            echo "" >&2
        fi
    fi

    # Clean up the input: strip carriage returns and leading/trailing whitespace
    user_val=$(echo "$user_val" | tr -d '\r' | xargs)
    printf -v "$var_name" "%s" "$user_val"
    return $status
}

print_header() {
    local ver
    ver=$(read_suite_version)
    clear
    _pi_echo "==========================================================="
    _pi_echo "      Raspberry Pi Maintenance Suite Manager"
    echo "                      $ver"
    _pi_echo "==========================================================="
    echo ""
}

is_installed() {
    command -v "$1" &> /dev/null
}

skip_pi_only_task() {
    local script="$1"
    [ "$IS_PI" == "false" ] && [ "$script" == "update_pip.sh" ]
}

task_uses_user_cron() {
    [ "$1" == "update_pi_apps.sh" ]
}

check_dependencies() {
    if ! _ensure_install_helpers; then
        return 1
    fi
    _pi_echo "Checking dependencies..."

    if ! is_installed curl; then
        _pi_echo "Installing curl..."
        if ! pkg_install curl; then
            _pi_echo "Warning: Failed to install curl."
        fi
    fi

    if ! has_mail_sender; then
        _pi_echo "Mail sender not found. Installing mail-transport packages..."
        if pkg_install mail-transport; then
            _pi_echo "Mail transport installed successfully."
        else
            _pi_echo "Warning: Failed to install mail transport. Email notifications will be disabled."
        fi
    fi

    # Whiptail powers the default interactive UI; failure is non-fatal (text fallback).
    if ! is_installed whiptail; then
        _pi_echo "whiptail not found. Installing whiptail..."
        if pkg_install whiptail; then
            _pi_echo "whiptail installed successfully."
        else
            _pi_echo "Warning: Failed to install whiptail. Falling back to text UI."
        fi
    fi
}

# --- Whiptail / UI selection helpers ---

_close_wizard_ui_fds() {
    # KCOV_EXCL_START
    if [ -n "${INSTALL_UI_IN_FD:-}" ] && [ "${INSTALL_UI_IN_FD}" != "0" ]; then
        exec {INSTALL_UI_IN_FD}<&- || true
        INSTALL_UI_IN_FD=
    fi
    if [ -n "${INSTALL_UI_OUT_FD:-}" ] && [ "${INSTALL_UI_OUT_FD}" != "1" ]; then
        exec {INSTALL_UI_OUT_FD}>&- || true
        INSTALL_UI_OUT_FD=
    fi
    # KCOV_EXCL_STOP
}

_has_open_wizard_ui_fds() {
    [ -n "${INSTALL_UI_IN_FD:-}" ] && [ -n "${INSTALL_UI_OUT_FD:-}" ]
}

_can_open_wizard_ui_tty() {
    [ "${INSTALL_FAKE_NO_TTY:-0}" = "1" ] && return 1
    { [ -t 0 ] || [ -c /dev/tty ]; } || return 1
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

_open_wizard_ui_fd() {
    [ "${INSTALL_FAKE_NO_TTY:-0}" = "1" ] && return 1
    _has_open_wizard_ui_fds && return 0

    # Test mock path: no real TTY required when whiptail is explicitly enabled.
    if [ "${TEST_MODE}" = "true" ] && [ "${INSTALL_USE_WHIPTAIL}" = "1" ]; then
        INSTALL_UI_IN_FD=0
        INSTALL_UI_OUT_FD=1
        return 0
    fi

    # KCOV_EXCL_START
    _can_open_wizard_ui_tty || return 1
    exec {INSTALL_UI_IN_FD}< /dev/tty || return 1
    if ! exec {INSTALL_UI_OUT_FD}> /dev/tty; then
        exec {INSTALL_UI_IN_FD}<&- || true
        INSTALL_UI_IN_FD=
        return 1
    fi
    return 0
    # KCOV_EXCL_STOP
}

_is_whiptail_cancel() {
    local rc="$1"
    [ "$rc" -eq 1 ] || [ "$rc" -eq 255 ]
}

can_use_whiptail() {
    [ "${INSTALL_FORCE_TEXT_UI}" = "1" ] && return 1
    [ "${INSTALL_USE_WHIPTAIL}" = "0" ] && return 1

    # Stdin-driven automated tests default to text UI unless explicitly enabled.
    if [ "${TEST_MODE}" = "true" ] && [ "${INSTALL_USE_WHIPTAIL}" != "1" ]; then
        return 1
    fi

    is_installed whiptail || return 1
    _open_wizard_ui_fd || return 1
    return 0
}

select_ui_mode() {
    if can_use_whiptail; then
        INSTALL_UI_MODE="whiptail"
    else
        INSTALL_UI_MODE="text"
        _close_wizard_ui_fds
    fi
}

_wt_fallback_to_text() {
    _pi_echo "Whiptail UI unavailable; switching to text interface." >&2
    INSTALL_UI_MODE="text"
    INSTALL_FORCE_TEXT_UI=1
    _close_wizard_ui_fds
}

_run_whiptail() {
    local out_file="${1:-}"
    shift || true

    if [ -n "$out_file" ]; then
        # KCOV_EXCL_START
        if _has_open_wizard_ui_fds && [ "${INSTALL_UI_IN_FD}" != "0" ]; then
            whiptail "$@" --output-fd 3 \
                <&"$INSTALL_UI_IN_FD" >&"$INSTALL_UI_OUT_FD" 2>&"$INSTALL_UI_OUT_FD" 3> "$out_file"
        else
            # KCOV_EXCL_STOP
            whiptail "$@" --output-fd 3 3> "$out_file"
        fi
        return $?
    fi

    # KCOV_EXCL_START
    if _has_open_wizard_ui_fds && [ "${INSTALL_UI_IN_FD}" != "0" ]; then
        whiptail "$@" <&"$INSTALL_UI_IN_FD" >&"$INSTALL_UI_OUT_FD" 2>&"$INSTALL_UI_OUT_FD"
    else
        # KCOV_EXCL_STOP
        whiptail "$@"
    fi
}

_wt_capture() {
    # Runs a value-returning dialog; prints result on stdout. Returns whiptail status.
    local tmp result rc=0
    tmp=$(mktemp) || return 2
    _run_whiptail "$tmp" "$@"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        result=$(cat "$tmp")
        rm -f "$tmp"
        printf '%s' "$result"
        return 0
    fi
    rm -f "$tmp"
    return "$rc"
}

wt_msgbox() {
    local title="$1" message="$2" height="${3:-10}" width="${4:-70}"
    _run_whiptail "" --title "$title" --msgbox "$message" "$height" "$width"
}

wt_yesno() {
    local title="$1" message="$2" height="${3:-10}" width="${4:-70}"
    local yes_btn="${5:-}" no_btn="${6:-}"
    if [ -n "$yes_btn" ] && [ -n "$no_btn" ]; then
        _run_whiptail "" --title "$title" \
            --yes-button "$yes_btn" --no-button "$no_btn" \
            --yesno "$message" "$height" "$width"
    else
        _run_whiptail "" --title "$title" --yesno "$message" "$height" "$width"
    fi
}

wt_inputbox() {
    local title="$1" message="$2" height="${3:-10}" width="${4:-70}" default="${5:-}"
    _wt_capture --title "$title" --inputbox "$message" "$height" "$width" "$default"
}

wt_passwordbox() {
    local title="$1" message="$2" height="${3:-10}" width="${4:-70}"
    _wt_capture --title "$title" --passwordbox "$message" "$height" "$width"
}

wt_menu() {
    local title="$1" message="$2" height="$3" width="$4" menu_height="$5"
    shift 5
    _wt_capture --title "$title" --menu "$message" "$height" "$width" "$menu_height" "$@"
}

cron_to_human() {
    local cron_str=$1

    if [[ -z "$cron_str" || "$cron_str" == "-" ]]; then
        _pi_echo "-"
        return
    fi

    local m
    m=$(echo "$cron_str" | awk '{print $1}')
    local h
    h=$(echo "$cron_str" | awk '{print $2}')
    local dom
    dom=$(echo "$cron_str" | awk '{print $3}')
    local mon
    mon=$(echo "$cron_str" | awk '{print $4}')
    local dow
    dow=$(echo "$cron_str" | awk '{print $5}')

    # Pad time
    if [[ ${#m} -eq 1 ]]; then m="0$m"; fi
    if [[ ${#h} -eq 1 ]]; then h="0$h"; fi

    if [[ "$dom" == "*" && "$mon" == "*" && "$dow" == "*" ]]; then
        _pi_echof "Daily @ %s:%s" "$h" "$m"
    elif [[ "$dom" == "*" && "$mon" == "*" && "$dow" != "*" ]]; then
        case $dow in
            0 | 7) day=$(_pi_gettext "Sun") ;;
            1) day=$(_pi_gettext "Mon") ;;
            2) day=$(_pi_gettext "Tue") ;;
            3) day=$(_pi_gettext "Wed") ;;
            4) day=$(_pi_gettext "Thu") ;;
            5) day=$(_pi_gettext "Fri") ;;
            6) day=$(_pi_gettext "Sat") ;;
            *) day=$(_pi_gettextf "Dow %s" "$dow") ;;
        esac
        _pi_echof "Weekly %s @ %s:%s" "$day" "$h" "$m"
    elif [[ "$dom" != "*" && "$mon" == "*" && "$dow" == "*" ]]; then
        _pi_echof "Monthly %s @ %s:%s" "$dom" "$h" "$m"
    else
        _pi_echo "Custom Schedule"
    fi
}

validate_email_address() {
    local user_email="$1"
    [[ "$user_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

save_email_configuration() {
    local user_email="$1"
    local app_pass="$2"

    _pi_echo "Saving configuration..."
    if command -v write_mail_config > /dev/null 2>&1; then
        write_mail_config "$user_email" "$app_pass"
    else
        # KCOV_EXCL_START
        # Pre-create with restrictive mode before writing secrets (TOCTOU).
        sudo mkdir -p "$(dirname "$SSMTP_CONF")"
        sudo touch "$SSMTP_CONF"
        sudo chmod 600 "$SSMTP_CONF"
        cat << EOF | sudo tee "$SSMTP_CONF" > /dev/null
root=$user_email
mailhub=smtp.gmail.com:587
AuthUser=$user_email
AuthPass=$app_pass
UseSTARTTLS=YES
UseTLS=YES
FromLineOverride=YES
hostname=$(hostname)
EOF
        sudo chown root:mail "$SSMTP_CONF" 2> /dev/null || sudo chown root:root "$SSMTP_CONF"
        sudo chmod 640 "$SSMTP_CONF"
        sudo touch "$REVALIASES"
        sudo chmod 600 "$REVALIASES"
        cat << EOF | sudo tee "$REVALIASES" > /dev/null
root:$user_email:smtp.gmail.com:587
$USER:$user_email:smtp.gmail.com:587
EOF
        sudo chmod 640 "$REVALIASES"
        # KCOV_EXCL_STOP
    fi
    sudo usermod -a -G mail "$USER" 2> /dev/null || true

    # Update scripts with new email
    if [ -d "$INSTALL_DIR" ]; then
        for file in "$INSTALL_DIR"/*.sh; do
            [ -f "$file" ] || continue
            sed -i "s/RECIPIENT_EMAIL=\".*\"/RECIPIENT_EMAIL=\"$user_email\"/" "$file"
        done
    fi

    # Configure cron MAILTO so that cron failures are sent to this email
    {
        echo "MAILTO=\"$user_email\""
        sudo crontab -l 2> /dev/null | grep -v "^MAILTO="
    } | sudo crontab -
    {
        echo "MAILTO=\"$user_email\""
        crontab -l 2> /dev/null | grep -v "^MAILTO="
    } | crontab -

    _pi_echo "Email configured successfully."
}

get_current_email_user() {
    if [ -f "$SSMTP_CONF" ]; then
        sudo grep "^AuthUser=" "$SSMTP_CONF" | cut -d= -f2
        return 0
    fi
    if [ -f "$MSMTP_CONF" ]; then
        sudo grep -E '^user\s+' "$MSMTP_CONF" | awk '{print $2}' | head -n 1
    fi
}

apply_task_schedule() {
    local script_name="$1"
    local sched="$2"

    if task_uses_user_cron "$script_name"; then
        (
            crontab -l 2> /dev/null | grep -v "$script_name"
            echo "$sched $INSTALL_DIR/$script_name >/dev/null 2>&1"
        ) | crontab -
    else
        (
            sudo crontab -l 2> /dev/null | grep -v "$script_name"
            echo "$sched $INSTALL_DIR/$script_name >/dev/null 2>&1"
        ) | sudo crontab -
    fi
}

# Rewrite existing suite crontab lines so cron MAILTO does not dump stdout/stderr.
quiet_suite_cron_jobs() {
    local i script_name line sched first
    for i in {1..7}; do
        script_name="${SCRIPTS[$i]}"
        if task_uses_user_cron "$script_name"; then
            line=$(crontab -l 2> /dev/null | grep -F "$script_name" | head -n 1) || true
        else
            line=$(sudo crontab -l 2> /dev/null | grep -F "$script_name" | head -n 1) || true
        fi
        [ -n "$line" ] || continue
        first=$(echo "$line" | awk '{print $1}')
        if [[ "$first" == @* ]]; then
            sched="$first"
        else
            sched=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
        fi
        [ -n "$sched" ] || continue
        apply_task_schedule "$script_name" "$sched"
    done
}

remove_task_schedule() {
    local script_name="$1"

    if task_uses_user_cron "$script_name"; then
        crontab -l 2> /dev/null | grep -v "$script_name" | crontab -
    else
        sudo crontab -l 2> /dev/null | grep -v "$script_name" | sudo crontab -
    fi
}

# --- Email (text + whiptail) ---

configure_email_text() {
    print_header
    _pi_echo "--- Email Configuration ---"

    local current_user=""
    if [ -f "$SSMTP_CONF" ]; then
        current_user=$(get_current_email_user)
        echo "Current Configured Email: $current_user"
        read_input "Do you want to reconfigure email? [y/N]: " confirm
        confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
        [[ ! "$confirm" == "y" ]] && return
    fi

    echo ""
    local user_email=""
    read_input "Enter Gmail address: " user_email
    if ! validate_email_address "$user_email"; then
        _pi_echo "Invalid email. returning to menu."
        read_input "Press Enter..." _
        return
    fi

    _pi_echo "Enter App Password (16-char, input hidden):"
    local app_pass=""
    read_input "" app_pass "true"
    # Remove all spaces (Google displays them as 'aaaa bbbb cccc dddd')
    app_pass=$(echo "$app_pass" | tr -d ' ')
    echo "" # Newline after secret input

    if [ -z "$app_pass" ]; then
        _pi_echo "Password empty. Returning."
        return
    fi

    save_email_configuration "$user_email" "$app_pass"
    sleep 1
}

configure_email_whiptail() {
    local current_user="" confirm_rc=0 user_email="" app_pass=""

    if [ -f "$SSMTP_CONF" ] && [ -s "$SSMTP_CONF" ]; then
        current_user=$(get_current_email_user)
        wt_yesno "$(_pi_gettext "Email Configuration")" \
            "Current email: ${current_user:-unknown}\n\nReconfigure email settings?" 10 70
        confirm_rc=$?
        if [ "$confirm_rc" -eq 255 ]; then
            return 1
        fi
        if [ "$confirm_rc" -eq 1 ]; then
            return 0
        fi
        if [ "$confirm_rc" -ne 0 ]; then
            return 2
        fi
    fi

    user_email=$(wt_inputbox "$(_pi_gettext "Email Configuration")" "$(_pi_gettext "Enter Gmail address:")" 10 70) || {
        local rc=$?
        _is_whiptail_cancel "$rc" && return 1
        return 2
    }
    user_email=$(echo "$user_email" | tr -d '\r' | xargs)
    if ! validate_email_address "$user_email"; then
        wt_msgbox "$(_pi_gettext "Email Configuration")" "$(_pi_gettext "Invalid email address.")" 8 50 || true
        return 0
    fi

    app_pass=$(wt_passwordbox "$(_pi_gettext "Email Configuration")" "$(_pi_gettext "Enter App Password (16-char):")" 10 70) || {
        local rc=$?
        _is_whiptail_cancel "$rc" && return 1
        return 2
    }
    app_pass=$(echo "$app_pass" | tr -d ' ' | tr -d '\r')
    if [ -z "$app_pass" ]; then
        wt_msgbox "$(_pi_gettext "Email Configuration")" "$(_pi_gettext "Password empty. Returning.")" 8 50 || true
        return 0
    fi

    save_email_configuration "$user_email" "$app_pass"
    wt_msgbox "$(_pi_gettext "Email Configuration")" "$(_pi_gettext "Email configured successfully.")" 8 50 || true
    return 0
}

configure_email_interactive() {
    if [ "${INSTALL_UI_MODE}" = "whiptail" ] || { [ -z "${INSTALL_UI_MODE}" ] && can_use_whiptail; }; then
        INSTALL_UI_MODE="whiptail"
        configure_email_whiptail
        local rc=$?
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
            return "$rc"
        fi
        _wt_fallback_to_text
    fi
    configure_email_text
}

show_email_config_text() {
    print_header
    _pi_echo "--- Current Email Settings ---"
    if [ -f "$SSMTP_CONF" ]; then
        user=$(sudo grep "^AuthUser=" "$SSMTP_CONF" | cut -d= -f2)
        hub=$(sudo grep "^mailhub=" "$SSMTP_CONF" | cut -d= -f2)
        echo "User:     $user"
        echo "Server:   $hub"
        _pi_echo "Password: [HIDDEN/MASKED]"
    else
        _pi_echo "No SSMTP configuration found."
    fi
    echo ""
    read_input "Press Enter to return..." _
}

show_email_config_whiptail() {
    local message
    if [ -f "$SSMTP_CONF" ]; then
        user=$(sudo grep "^AuthUser=" "$SSMTP_CONF" | cut -d= -f2)
        hub=$(sudo grep "^mailhub=" "$SSMTP_CONF" | cut -d= -f2)
        message="User:     $user\nServer:   $hub\nPassword: [HIDDEN/MASKED]"
    else
        message="No SSMTP configuration found."
    fi
    wt_msgbox "$(_pi_gettext "Current Email Settings")" "$message" 12 60
    local rc=$?
    _is_whiptail_cancel "$rc" && return 1
    [ "$rc" -eq 0 ] && return 0
    return 2
}

show_email_config() {
    if [ "${INSTALL_UI_MODE}" = "whiptail" ] || { [ -z "${INSTALL_UI_MODE}" ] && can_use_whiptail; }; then
        INSTALL_UI_MODE="whiptail"
        show_email_config_whiptail
        local rc=$?
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
            return "$rc"
        fi
        _wt_fallback_to_text
    fi
    show_email_config_text
}

# Write via temp + mv so a running cron script keeps its old inode.
_install_atomic_mv() {
    local tmp="$1"
    local dest="$2"
    chmod 600 "$tmp" 2> /dev/null || true
    mv -f "$tmp" "$dest"
}

_install_atomic_copy() {
    local src="$1"
    local dest="$2"
    local tmp
    mkdir -p "$(dirname "$dest")"
    tmp=$(mktemp "$(dirname "$dest")/.rpi-install.XXXXXX")
    if ! cat "$src" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    _install_atomic_mv "$tmp" "$dest"
}

_install_atomic_curl() {
    local url="$1"
    local dest="$2"
    local tmp
    mkdir -p "$(dirname "$dest")"
    tmp=$(mktemp "$(dirname "$dest")/.rpi-install.XXXXXX")
    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    _install_atomic_mv "$tmp" "$dest"
}

download_scripts() {
    _pi_echo "Downloading/Updating scripts..."
    mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/lib"

    # Get email for injection
    local email_to_inject="your_email@gmail.com"
    if [ -f "$SSMTP_CONF" ]; then
        email_to_inject=$(sudo grep "^AuthUser=" "$SSMTP_CONF" | cut -d= -f2)
    elif [ -f "$MSMTP_CONF" ]; then
        email_to_inject=$(sudo grep -E '^user\s+' "$MSMTP_CONF" | awk '{print $2}' | head -n 1)
    fi

    # Shared libraries used by maintenance scripts (apt/dnf/pacman + mail + UI helpers)
    local lib_file lib_src
    for lib_file in os_pkg.sh mail_send.sh ui_msg.sh; do
        lib_src=""
        if [ -f "$_INSTALL_ROOT/lib/$lib_file" ]; then
            lib_src="$_INSTALL_ROOT/lib/$lib_file"
        fi
        if [ -n "$lib_src" ]; then
            if ! _install_atomic_copy "$lib_src" "$INSTALL_DIR/lib/$lib_file"; then
                _pi_echof "Error downloading lib/%s" "$lib_file"
                continue
            fi
        else
            if ! _install_atomic_curl "$RAW_URL/lib/$lib_file" "$INSTALL_DIR/lib/$lib_file"; then
                _pi_echof "Error downloading lib/%s" "$lib_file"
                continue
            fi
        fi
        chmod +x "$INSTALL_DIR/lib/$lib_file"
    done

    for i in {1..7}; do
        local script="${SCRIPTS[$i]}"

        # Skip Pi-only script on non-Pi hardware
        if skip_pi_only_task "$script"; then
            continue
        fi

        if ! _install_atomic_curl "$RAW_URL/scripts/$script" "$INSTALL_DIR/$script"; then
            _pi_echof "Error downloading %s" "$script"
            continue
        fi

        if [ -f "$INSTALL_DIR/$script" ]; then
            sed -i "s/RECIPIENT_EMAIL=\".*\"/RECIPIENT_EMAIL=\"$email_to_inject\"/" "$INSTALL_DIR/$script"
            chmod +x "$INSTALL_DIR/$script"
        else
            _pi_echof "Error downloading %s" "$script"
        fi
    done
    _pi_echo "Scripts updated."
    write_installed_version
    sleep 1
}

# Suite version SSOT: root VERSION (next to install.sh), else installed .version, else RAW_URL/VERSION.
read_suite_version() {
    local version=""

    if [ -n "${SUITE_VERSION:-}" ]; then
        printf '%s' "$SUITE_VERSION"
        return 0
    fi

    if [ -f "$_INSTALL_ROOT/VERSION" ]; then
        version=$(tr -d '[:space:]' < "$_INSTALL_ROOT/VERSION")
    elif [ -f "${INSTALL_DIR:-}/.version" ]; then
        version=$(tr -d '[:space:]' < "$INSTALL_DIR/.version")
    else
        version=$(curl -fsSL --max-time 10 "$RAW_URL/VERSION" 2> /dev/null | tr -d '[:space:]' || true)
    fi

    SUITE_VERSION="${version:-unknown}"
    printf '%s' "$SUITE_VERSION"
}

# Copy suite version into $INSTALL_DIR/.version from VERSION SSOT (local file or RAW_URL).
# Do not reuse an existing .version here — that would block RAW_URL refresh / one-liner installs.
write_installed_version() {
    local version=""
    _pi_echo "Updating version tracking..."
    SUITE_VERSION=""

    if [ -f "$_INSTALL_ROOT/VERSION" ]; then
        version=$(tr -d '[:space:]' < "$_INSTALL_ROOT/VERSION")
    else
        version=$(curl -fsSL --max-time 10 "$RAW_URL/VERSION" 2> /dev/null | tr -d '[:space:]' || true)
    fi

    if [ -n "$version" ]; then
        printf '%s\n' "$version" > "$INSTALL_DIR/.version"
        SUITE_VERSION="$version"
        _pi_echof "Version set to: %s" "$version"
    else
        _pi_echof "Warning: could not read VERSION (local or %s)." "$RAW_URL/VERSION"
    fi
}

get_task_status() {
    local script_name=$1
    local is_root=$2
    local line=""

    if [ "$is_root" == "true" ]; then
        line=$(sudo crontab -l 2> /dev/null | grep "$script_name")
    else
        line=$(crontab -l 2> /dev/null | grep "$script_name")
    fi

    if [ -z "$line" ]; then
        _pi_echo "DISABLED|-"
    else
        # Extract schedule part (remove the command path)
        local sched
        sched=${line% "$INSTALL_DIR"/*}
        echo "ENABLED|$sched"
    fi
}

toggle_task() {
    local id=$1
    local script_name="${SCRIPTS[$id]}"
    local default_sched="${DEFAULTS[$id]}"
    local is_root="true"

    # Pi-Apps is the only user-crontab script
    if task_uses_user_cron "$script_name"; then
        is_root="false"
    fi

    local status_info
    status_info=$(get_task_status "$script_name" "$is_root")
    local state
    state=$(echo "$status_info" | cut -d'|' -f1)
    local current_sched
    current_sched=$(echo "$status_info" | cut -d'|' -f2)

    echo ""
    _pi_echof "Task: %s" "$(_pi_task_name "$id")"
    echo "Current Status: $state"
    if [ "$state" == "ENABLED" ]; then
        echo "Current Schedule: $current_sched"
    fi
    echo ""

    if [ "$state" == "ENABLED" ]; then
        read_input "Do you want to DISABLE this task? [y/N] (Enter 'e' to edit time): " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
        if [[ "$choice" == "y" ]]; then
            remove_task_schedule "$script_name"
            _pi_echo "Task disabled."
        elif [[ "$choice" == "e" ]]; then
            read_input "Enter new cron schedule (Default: $default_sched): " new_time
            new_time=${new_time:-$default_sched}
            apply_task_schedule "$script_name" "$new_time"
            _pi_echo "Schedule updated."
        fi
    else
        read_input "Do you want to ENABLE this task? [y/N]: " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
        if [[ "$choice" == "y" ]]; then
            read_input "Enter cron schedule (Default: $default_sched): " new_time
            new_time=${new_time:-$default_sched}
            apply_task_schedule "$script_name" "$new_time"
            _pi_echo "Task enabled."
        fi
    fi
    sleep 1
}

toggle_task_whiptail() {
    local id=$1
    local script_name="${SCRIPTS[$id]}"
    local default_sched="${DEFAULTS[$id]}"
    local is_root="true"
    local choice new_time status_info state current_sched action_rc=0

    if task_uses_user_cron "$script_name"; then
        is_root="false"
    fi

    status_info=$(get_task_status "$script_name" "$is_root")
    state=$(echo "$status_info" | cut -d'|' -f1)
    current_sched=$(echo "$status_info" | cut -d'|' -f2)

    if [ "$state" == "ENABLED" ]; then
        choice=$(wt_menu "$(_pi_gettextf "Task: %s" "$(_pi_task_name "$id")")" \
            "Status: ENABLED\nSchedule: $current_sched" 14 70 3 \
            "disable" "Disable this task" \
            "edit" "Edit cron schedule" \
            "back" "Return without changes") || {
            action_rc=$?
            _is_whiptail_cancel "$action_rc" && return 1
            return 2
        }
        case "$choice" in
            disable)
                remove_task_schedule "$script_name"
                _pi_echo "Task disabled."
                ;;
            edit)
                new_time=$(wt_inputbox "$(_pi_gettext "Edit Schedule")" "$(_pi_gettext "Enter cron schedule:")" 10 70 "$current_sched") || {
                    action_rc=$?
                    _is_whiptail_cancel "$action_rc" && return 1
                    return 2
                }
                new_time=${new_time:-$default_sched}
                apply_task_schedule "$script_name" "$new_time"
                _pi_echo "Schedule updated."
                ;;
        esac
    else
        wt_yesno "$(_pi_gettextf "Task: %s" "$(_pi_task_name "$id")")" "Enable this task?\nDefault: $default_sched" 10 70 || {
            action_rc=$?
            if [ "$action_rc" -eq 255 ]; then
                return 1
            fi
            if [ "$action_rc" -eq 1 ]; then
                return 0
            fi
            return 2
        }
        new_time=$(wt_inputbox "$(_pi_gettext "Enable Task")" "$(_pi_gettext "Enter cron schedule:")" 10 70 "$default_sched") || {
            action_rc=$?
            _is_whiptail_cancel "$action_rc" && return 1
            return 2
        }
        new_time=${new_time:-$default_sched}
        apply_task_schedule "$script_name" "$new_time"
        _pi_echo "Task enabled."
    fi
    return 0
}

_confirm_reboot_tasks_text() {
    local confirm_reboot_run=""
    _pi_echo "Warning: One or more enabled tasks may reboot the system and terminate this session."
    read_input "Proceed with running enabled tasks now? [y/N]: " confirm_reboot_run
    confirm_reboot_run=$(echo "$confirm_reboot_run" | tr '[:upper:]' '[:lower:]')
    [ "$confirm_reboot_run" = "y" ]
}

_confirm_reboot_tasks_whiptail() {
    local message rc
    message="Warning: One or more enabled tasks may reboot the system and terminate this session.\n\nProceed?"
    wt_yesno "$(_pi_gettext "Run Enabled Tasks Now")" "$message" 12 70
    rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 1 ] || [ "$rc" -eq 255 ] && return 1
    return 2
}

_execute_enabled_tasks() {
    local ran_any=false
    local failed_any=false

    for i in {1..7}; do
        local script_name="${SCRIPTS[$i]}"
        local task_name="${NAMES[$i]}"
        local is_root="true"
        local status_info=""
        local state=""

        if skip_pi_only_task "$script_name"; then
            continue
        fi

        if task_uses_user_cron "$script_name"; then
            is_root="false"
        fi

        status_info=$(get_task_status "$script_name" "$is_root")
        state=$(echo "$status_info" | cut -d'|' -f1)

        if [ "$state" != "ENABLED" ]; then
            continue
        fi

        ran_any=true
        echo ""
        echo "Running: $task_name ($script_name)"

        if [ ! -f "$INSTALL_DIR/$script_name" ]; then
            echo "  Skipped: Script not found: $INSTALL_DIR/$script_name"
            failed_any=true
            continue
        fi

        if [ "$script_name" == "update_pi_apps.sh" ] && [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
            # KCOV_EXCL_START
            if sudo -u "$SUDO_USER" bash "$INSTALL_DIR/$script_name"; then
                _pi_echo "  Success"
            else
                _pi_echo "  Failed"
                failed_any=true
            fi
            # KCOV_EXCL_STOP
        else
            if bash "$INSTALL_DIR/$script_name"; then
                _pi_echo "  Success"
            else
                _pi_echo "  Failed"
                failed_any=true
            fi
        fi
    done

    echo ""
    if [ "$ran_any" != "true" ]; then
        _pi_echo "No enabled tasks found."
    elif [ "$failed_any" == "true" ]; then
        _pi_echo "Completed with failures."
    else
        _pi_echo "All enabled tasks completed successfully."
    fi
}

_has_enabled_reboot_task() {
    local reboot_script reboot_status_info reboot_state
    for reboot_script in "update_pi_os.sh" "update_pi_firmware.sh" "update_samsung_ssd.sh"; do
        reboot_status_info=$(get_task_status "$reboot_script" "true")
        reboot_state=$(echo "$reboot_status_info" | cut -d'|' -f1)
        if [ "$reboot_state" == "ENABLED" ]; then
            return 0
        fi
    done
    return 1
}

run_enabled_tasks_now() {
    local use_wt=false confirm_rc=0

    if [ "${INSTALL_UI_MODE}" = "whiptail" ] || { [ -z "${INSTALL_UI_MODE}" ] && can_use_whiptail; }; then
        use_wt=true
        INSTALL_UI_MODE="whiptail"
    fi

    if [ "$use_wt" != "true" ]; then
        print_header
    fi
    _pi_echo "--- Run Enabled Tasks Now ---"

    if _has_enabled_reboot_task; then
        if [ "$use_wt" = "true" ]; then
            _confirm_reboot_tasks_whiptail
            confirm_rc=$?
            if [ "$confirm_rc" -eq 2 ]; then
                _wt_fallback_to_text
                use_wt=false
                if ! _confirm_reboot_tasks_text; then
                    _pi_echo "Cancelled: Enabled tasks were not run."
                    read_input "Press Enter to return..." _
                    return
                fi
            elif [ "$confirm_rc" -ne 0 ]; then
                _pi_echo "Cancelled: Enabled tasks were not run."
                wt_msgbox "$(_pi_gettext "Run Enabled Tasks Now")" "$(_pi_gettext "Cancelled: Enabled tasks were not run.")" 8 60 || true
                return
            fi
        else
            if ! _confirm_reboot_tasks_text; then
                _pi_echo "Cancelled: Enabled tasks were not run."
                read_input "Press Enter to return..." _
                return
            fi
        fi
    fi

    _execute_enabled_tasks

    if [ "$use_wt" = "true" ] && [ "${INSTALL_UI_MODE}" = "whiptail" ]; then
        wt_msgbox "$(_pi_gettext "Run Enabled Tasks Now")" \
            "$(_pi_gettext "Finished running enabled tasks.\nSee terminal output for details.")" 10 60 || true
    else
        read_input "Press Enter to return..." _
    fi
}

manage_tasks_ui_text() {
    while true; do
        print_header
        _pi_echo "   Task Status Manager"
        _pi_echo "   -------------------"
        # Expanded columns for Readability
        printf "   %-3s %-30s %-10s %-20s %-15s\n" "ID" "Task Name" "Status" "Human Time" "Cron Raw"
        _pi_echo "   ----------------------------------------------------------------------------------"

        for i in {1..7}; do
            local script="${SCRIPTS[$i]}"
            local name="${NAMES[$i]}"

            # Skip Pi-only script on non-Pi hardware
            if skip_pi_only_task "$script"; then
                continue
            fi

            local is_root="true"
            task_uses_user_cron "$script" && is_root="false"

            local info
            info=$(get_task_status "$script" "$is_root")
            local state
            state=$(echo "$info" | cut -d'|' -f1)
            local sched
            sched=$(echo "$info" | cut -d'|' -f2)

            local human_time
            human_time=$(cron_to_human "$sched")

            printf "   %-3s %-30s %-10s %-20s %-15s\n" "$i" "$name" "$state" "$human_time" "$sched"
        done
        echo ""
        _pi_echo "   Enter ID to toggle/edit, or '0' to return to Main Menu."
        local sel=""
        if ! read_input "   Selection: " sel; then
            _pi_echo "EOF detected"
            return
        fi

        if [[ "$sel" == "0" ]]; then return; fi
        if [[ "$sel" =~ ^[1-7]$ ]]; then
            toggle_task "$sel"
        fi
    done
}

_build_task_menu_items() {
    # Prints whiptail menu pairs: TAG DESC (stdout)
    local i script name is_root info state sched human_time
    for i in {1..7}; do
        script="${SCRIPTS[$i]}"
        name="${NAMES[$i]}"
        if skip_pi_only_task "$script"; then
            continue
        fi
        is_root="true"
        task_uses_user_cron "$script" && is_root="false"
        info=$(get_task_status "$script" "$is_root")
        state=$(echo "$info" | cut -d'|' -f1)
        sched=$(echo "$info" | cut -d'|' -f2)
        human_time=$(cron_to_human "$sched")
        printf '%s\n%s\n' "$i" "$name [$state] $human_time"
    done
}

manage_tasks_ui_whiptail() {
    local sel items_args=() tag desc rc=0

    while true; do
        items_args=()
        while IFS= read -r tag && IFS= read -r desc; do
            items_args+=("$tag" "$desc")
        done < <(_build_task_menu_items)
        items_args+=("0" "$(_pi_gettext "Return to Main Menu")")

        sel=$(wt_menu "$(_pi_gettext "Task Status Manager")" \
            "Select a task to toggle/edit.\nSpace is unused; Enter selects. Esc cancels." \
            20 78 10 "${items_args[@]}") || {
            rc=$?
            _is_whiptail_cancel "$rc" && return 1
            return 2
        }

        # Empty selection (e.g. exhausted automated input) returns to caller.
        if [[ -z "$sel" || "$sel" == "0" ]]; then
            return 0
        fi
        if [[ "$sel" =~ ^[1-7]$ ]]; then
            toggle_task_whiptail "$sel" || {
                rc=$?
                [ "$rc" -eq 1 ] && continue
                return 2
            }
        fi
    done
}

manage_tasks_ui() {
    if [ "${INSTALL_UI_MODE}" = "whiptail" ] || { [ -z "${INSTALL_UI_MODE}" ] && can_use_whiptail; }; then
        INSTALL_UI_MODE="whiptail"
        manage_tasks_ui_whiptail
        local rc=$?
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
            return "$rc"
        fi
        _wt_fallback_to_text
    fi
    manage_tasks_ui_text
}

_enable_selected_fresh_tasks_text() {
    echo ""
    _pi_echo "Setting up default schedules..."
    _pi_echo "Select which tasks to enable. Press Enter to accept default [Y]."

    for i in {1..7}; do
        local script="${SCRIPTS[$i]}"
        local name="${NAMES[$i]}"

        if skip_pi_only_task "$script"; then
            echo "Skipping $name (Raspberry Pi hardware not detected)"
            continue
        fi

        local sched="${DEFAULTS[$i]}"
        local human
        human=$(cron_to_human "$sched")

        read_input "$i. Enable $name ($human)? [Y/n]: " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
        choice=${choice:-y}

        if [[ "$choice" == "y" ]]; then
            apply_task_schedule "$script" "$sched"
            echo "Enabled $name"
        else
            echo "Skipped $name"
        fi
        echo "" # Newline separator after status
    done
}

_fresh_task_checklist_items() {
    local i script name human
    for i in {1..7}; do
        script="${SCRIPTS[$i]}"
        name="${NAMES[$i]}"
        if skip_pi_only_task "$script"; then
            continue
        fi
        human=$(cron_to_human "${DEFAULTS[$i]}")
        printf '%s\n%s\n%s\n' "$i" "$name ($human)" "ON"
    done
}

_enable_selected_fresh_tasks_whiptail() {
    local choice_tmp selected id script sched rc=0
    local items_args=() tag desc state
    local message

    message=$'
'"$(_pi_gettext "[4/4] Select maintenance tasks to enable.")"$'
'
    message+=$'
'"$(_pi_gettext "All tasks are ON by default. Space toggles. Enter confirms.")"$'
'
    message+=$'
'"$(_pi_gettext "Esc / Cancel aborts the installer without enabling tasks.")"$'
'
    message+=$'
'"$(_pi_gettext "Selected tasks use their default weekly schedules.")"$'
'

    while IFS= read -r tag && IFS= read -r desc && IFS= read -r state; do
        items_args+=("$tag" "$desc" "$state")
    done < <(_fresh_task_checklist_items)

    choice_tmp=$(mktemp) || return 2
    _run_whiptail "$choice_tmp" --title "$(_pi_gettext "Raspberry Pi Maintenance Suite")" \
        --separate-output --checklist "$message" 22 78 8 "${items_args[@]}" || {
        rc=$?
        rm -f "$choice_tmp"
        _is_whiptail_cancel "$rc" && return 1
        return 2
    }

    while IFS= read -r selected; do
        [ -z "$selected" ] && continue
        id="$selected"
        script="${SCRIPTS[$id]}"
        sched="${DEFAULTS[$id]}"
        apply_task_schedule "$script" "$sched"
        _pi_echof "Enabled %s" "$(_pi_task_name "$id")"
    done < "$choice_tmp"
    rm -f "$choice_tmp"
    return 0
}

_abort_fresh_install_whiptail() {
    local reason="${1:-Installation cancelled.}"
    echo "$reason"
    wt_msgbox "$(_pi_gettext "Installation Cancelled")" "$reason" 9 70 || true
}

_enable_default_fresh_tasks() {
    local i script name sched
    for i in {1..7}; do
        script="${SCRIPTS[$i]}"
        name="${NAMES[$i]}"
        if skip_pi_only_task "$script"; then
            echo "Skipping $name (Raspberry Pi hardware not detected)"
            continue
        fi
        sched="${DEFAULTS[$i]}"
        apply_task_schedule "$script" "$sched"
        echo "Enabled $name"
    done
}

# Non-interactive matrix/CI fresh install (no stdin blank-line protocol, no manager menu).
run_fresh_install_matrix() {
    local email="${MATRIX_EMAIL:?MATRIX_EMAIL must be set}"
    local pass="${MATRIX_PASS:?MATRIX_PASS must be set}"

    print_header
    _pi_echof "Welcome to the One-Line Installer (%s)." "$(read_suite_version)"
    _pi_echo "Matrix/non-interactive fresh install."
    echo ""
    check_dependencies
    save_email_configuration "$email" "$pass"
    download_scripts
    _enable_default_fresh_tasks
    echo ""
    _pi_echo "Installation Complete!"
}

_run_fresh_install_text_after_deps() {
    print_header
    _pi_echof "Welcome to the One-Line Installer (%s)." "$(read_suite_version)"
    _pi_echo "This wizard will set up your email and default schedules."
    echo ""
    configure_email_text
    download_scripts
    _enable_selected_fresh_tasks_text
    echo ""
    _pi_echo "Installation Complete!"
    read_input "Press Enter to open the Manager Menu..." _
    main_menu_text
}

run_fresh_install_text() {
    check_dependencies
    _run_fresh_install_text_after_deps
}

run_fresh_install_whiptail() {
    local rc=0
    local welcome_msg download_msg ver
    ver=$(read_suite_version)
    echo "Raspberry Pi Maintenance Suite $ver"

    check_dependencies

    welcome_msg="$(_pi_gettextf "Suite version: %s" "$ver")"
    welcome_msg+=$'

'"$(_pi_gettext "[1/4] Welcome")"
    welcome_msg+=$'

'"$(_pi_gettext "This wizard configures email, downloads scripts, and schedules maintenance tasks.")"
    welcome_msg+=$'

'"$(_pi_gettext "Choose Continue to proceed, or Cancel to abort without installing.")"
    wt_yesno "$(_pi_gettextf "Raspberry Pi Maintenance Suite %s" "$ver")" "$welcome_msg" 16 70 \
        "$(_pi_gettext "Continue")" "$(_pi_gettext "Cancel")" || {
        rc=$?
        if _is_whiptail_cancel "$rc"; then
            _abort_fresh_install_whiptail "Installation cancelled before setup."
            return 1
        fi
        return 2
    }

    _pi_echo "[2/4] Email configuration..."
    configure_email_whiptail || {
        rc=$?
        if [ "$rc" -eq 1 ]; then
            _abort_fresh_install_whiptail "Installation cancelled during email setup."
            return 1
        fi
        return 2
    }

    download_msg='[3/4] Download scripts'
    download_msg+=$'\n\nScripts will be installed to:\n'"$INSTALL_DIR"
    download_msg+=$'\n\nChoose Download to continue, or Cancel to abort.'
    wt_yesno "$(_pi_gettext "Download Scripts")" "$download_msg" 14 70 "$(_pi_gettext "Download")" "$(_pi_gettext "Cancel")" || {
        rc=$?
        if _is_whiptail_cancel "$rc"; then
            _abort_fresh_install_whiptail "Installation cancelled before downloading scripts."
            return 1
        fi
        return 2
    }

    _pi_echo "[3/4] Downloading scripts..."
    download_scripts

    _pi_echo "[4/4] Task selection..."
    _enable_selected_fresh_tasks_whiptail || {
        rc=$?
        if [ "$rc" -eq 1 ]; then
            _abort_fresh_install_whiptail \
                "Installation cancelled during task selection. Scripts may already be on disk under $INSTALL_DIR."
            return 1
        fi
        return 2
    }

    wt_msgbox "$(_pi_gettext "Installation Complete")" \
        "Setup finished successfully.\nOpening the Manager menu next." 10 60 || true
    main_menu_whiptail
}

run_fresh_install() {
    select_ui_mode
    if [ "${INSTALL_UI_MODE}" = "whiptail" ]; then
        run_fresh_install_whiptail
        local rc=$?
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
            return "$rc"
        fi
        _wt_fallback_to_text
        # Dependencies already checked in the whiptail path.
        _run_fresh_install_text_after_deps
        return
    fi
    run_fresh_install_text
}

_start_uninstall() {
    _pi_echo "Starting uninstallation process..."
    sleep 1
    if [ -f "./uninstall.sh" ]; then
        bash ./uninstall.sh
    else
        curl -sSL "$RAW_URL/uninstall.sh" | bash
    fi
    # Leave the process after uninstall when executed as a script; return in tests.
    if [ "${TEST_MODE}" == "true" ]; then
        return 0
    fi
    # KCOV_EXCL_START
    exit 0
    # KCOV_EXCL_STOP
}

main_menu_text() {
    while true; do
        print_header
        _pi_echo "   1. Configure Email Settings"
        _pi_echo "   2. View Current Email Config"
        _pi_echo "   3. Manage Tasks & Schedules (Enable/Disable)"
        _pi_echo "   4. Force Update Scripts (from GitHub)"
        _pi_echo "   5. Run Enabled Tasks Now"
        _pi_echo "   6. Uninstall Suite"
        _pi_echo "   0. Exit"
        echo ""

        # Prevent infinite loops during automated testing if input stream runs dry
        local opt=""
        if ! read_input "   Choose an option: " opt; then
            _pi_echo "EOF detected"
            return 0
        fi

        case $opt in
            1) configure_email_text ;;
            2) show_email_config_text ;;
            3) manage_tasks_ui_text ;;
            4) download_scripts ;;
            5)
                INSTALL_UI_MODE="text"
                run_enabled_tasks_now
                ;;
            6)
                read_input "Are you sure you want to uninstall? [y/N]: " un
                un=$(echo "$un" | tr '[:upper:]' '[:lower:]')
                if [[ "$un" == "y" ]]; then
                    _start_uninstall
                fi
                ;;
            0) return 0 ;;
            *)
                _pi_echof "Invalid option: '%s'" "$opt"
                sleep 2
                ;;
        esac
    done
}

main_menu_whiptail() {
    local opt rc=0 ver
    ver=$(read_suite_version)

    while true; do
        opt=$(wt_menu "$(_pi_gettext "Raspberry Pi Maintenance Suite Manager")" \
            "$(_pi_gettextf "Version: %s\n\nChoose an option. Enter selects. Esc cancels/exits." "$ver")" 18 70 8 \
            "1" "$(_pi_gettext "Configure Email Settings")" \
            "2" "$(_pi_gettext "View Current Email Config")" \
            "3" "$(_pi_gettext "Manage Tasks & Schedules")" \
            "4" "$(_pi_gettext "Force Update Scripts (from GitHub)")" \
            "5" "$(_pi_gettext "Run Enabled Tasks Now")" \
            "6" "$(_pi_gettext "Uninstall Suite")" \
            "0" "$(_pi_gettext "Exit")") || {
            rc=$?
            if _is_whiptail_cancel "$rc"; then
                return 0
            fi
            return 2
        }

        # Empty selection from exhausted input exits cleanly (automation safety).
        if [[ -z "$opt" ]]; then
            return 0
        fi

        case $opt in
            1)
                configure_email_whiptail || {
                    rc=$?
                    [ "$rc" -eq 1 ] && continue
                    return 2
                }
                ;;
            2)
                show_email_config_whiptail || {
                    rc=$?
                    [ "$rc" -eq 1 ] && continue
                    return 2
                }
                ;;
            3)
                manage_tasks_ui_whiptail || {
                    rc=$?
                    [ "$rc" -eq 1 ] && continue
                    return 2
                }
                ;;
            4) download_scripts ;;
            5)
                INSTALL_UI_MODE="whiptail"
                run_enabled_tasks_now
                ;;
            6)
                wt_yesno "$(_pi_gettext "Uninstall")" "$(_pi_gettext "Are you sure you want to uninstall?")" 10 60
                rc=$?
                if [ "$rc" -eq 0 ]; then
                    _start_uninstall
                elif [ "$rc" -eq 1 ] || [ "$rc" -eq 255 ]; then
                    continue
                else
                    return 2
                fi
                ;;
            0) return 0 ;;
        esac
    done
}

main_menu() {
    select_ui_mode
    if [ "${INSTALL_UI_MODE}" = "whiptail" ]; then
        main_menu_whiptail
        local rc=$?
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
            return "$rc"
        fi
        _wt_fallback_to_text
    fi
    main_menu_text
}

run_interactive() {
    # Allow bypassing TTY check for testing/automation
    if [ "${TEST_MODE}" == "true" ]; then
        "$@"
        return
    fi

    # KCOV_EXCL_START
    if [ -t 0 ]; then
        # Standard terminal execution
        "$@"
    elif [ -c /dev/tty ] && { true < /dev/tty; } 2> /dev/null; then
        # Piped execution (curl | bash). Input is now explicitly from terminal.
        "$@" < /dev/tty
    else
        # No TTY, non-interactive mode
        "$@"
    fi
    # KCOV_EXCL_STOP
}

# --- Entry Point ---
_require_update_helpers() {
    _ensure_install_helpers
}

install_main() {
    # Handle non-interactive update flag
    if [[ "${1:-}" == "--update" ]]; then
        echo "Updating Raspberry Pi Maintenance Suite ($(read_suite_version))..."
        if ! _require_update_helpers; then
            return 1
        fi
        check_dependencies
        download_scripts
        quiet_suite_cron_jobs
        return 0
    fi

    # Deterministic matrix/CI fresh install (no interactive prompts / menu).
    if [ "${INSTALL_MATRIX_FRESH:-0}" = "1" ]; then
        run_fresh_install_matrix
        return $?
    fi

    echo "Raspberry Pi Maintenance Suite $(read_suite_version)"

    # Check if already installed
    if [ -d "$INSTALL_DIR" ]; then
        # Ensure dependencies are present even on existing installs
        check_dependencies
        select_ui_mode
        run_interactive main_menu
    else
        run_interactive run_fresh_install
    fi
}

# Check if we are running as a script (not sourced)
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_main "$@"
fi
