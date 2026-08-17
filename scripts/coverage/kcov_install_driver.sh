#!/usr/bin/env bash
# kcov-traced driver for additional install.sh branches (include-path entry).
set +e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=../../tests/setup_mocks.sh
source ./tests/setup_mocks.sh
export TEST_MODE=true
export MOCK_IS_PI="${MOCK_IS_PI:-true}"
export INSTALL_DIR="/tmp/pi-scripts-install-cov"
export INSTALL_FORCE_TEXT_UI=1
export INSTALL_USE_WHIPTAIL=0
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/lib"
cp -a lib/*.sh "$INSTALL_DIR/lib/" 2> /dev/null || true

# shellcheck source=../../install.sh
source ./install.sh

skip_pi_only_task "update_pip.sh" || true
MOCK_IS_PI=false
skip_pi_only_task "update_pip.sh" || true
MOCK_IS_PI=true
task_uses_user_cron "update_pi_apps.sh" || true
is_installed curl || true
print_header || true

has_mail_sender() { return 1; }
is_installed() {
    case "$1" in
        curl | whiptail) return 1 ;;
        *) command -v "$1" > /dev/null 2>&1 ;;
    esac
}
check_dependencies || true
unset -f is_installed has_mail_sender
# Restore install.sh helpers (overridden above for dependency-failure branches).
is_installed() { command -v "$1" > /dev/null 2>&1; }

# shellcheck source=../../lib/os_pkg.sh
source ./lib/os_pkg.sh
# shellcheck source=../../lib/mail_send.sh
source ./lib/mail_send.sh

# Cover run_fresh_install whiptail→text fallback early (before other UI pollution).
export INSTALL_FORCE_TEXT_UI=0
export INSTALL_USE_WHIPTAIL=1
export INSTALL_UI_MODE=""
echo "fail" > "$MOCK_DIR/whiptail_mode"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib"
cp -a lib/*.sh "$INSTALL_DIR/lib/" 2> /dev/null || true
printf 'Y\nfb@test.com\npass\nn\nn\nn\nn\nn\nn\nn\n0\n' | run_fresh_install || true
echo "auto" > "$MOCK_DIR/whiptail_mode"
export INSTALL_FORCE_TEXT_UI=0

MSMTP_CONF="$MOCK_FS/etc/msmtprc"
mkdir -p "$(dirname "$MSMTP_CONF")" "$(dirname "$SSMTP_CONF")"
echo "user cov@example.com" > "$MSMTP_CONF"
_old_ssmtp="$SSMTP_CONF"
SSMTP_CONF="/tmp/missing-ssmtp-cov.conf"
get_current_email_user || true
SSMTP_CONF="$_old_ssmtp"
echo "AuthUser=cov@example.com" > "$SSMTP_CONF"
get_current_email_user || true

save_email_configuration "cov@example.com" "app-pass" || true
download_scripts || true
validate_email_address "bad" || true
validate_email_address "good@example.com" || true
for expr in "0 0 * * *" "0 0 * * 0" "0 0 * * 1" "0 0 * * 2" "0 0 * * 3" "0 0 * * 4" "0 0 * * 5" "0 0 * * 6" "0 0 1 * *" "1 2 3 4 5"; do
    cron_to_human "$expr" || true
done

select_ui_mode || true
can_use_whiptail || true
_close_wizard_ui_fds || true
_wt_fallback_to_text || true
_is_whiptail_cancel 255 || true
_is_whiptail_cancel 1 || true

printf '2\n0\n' | show_email_config_text || true
printf '0\n' | main_menu_text || true
printf 'n\n' | run_enabled_tasks_now || true

apply_task_schedule "update_pi_os.sh" "0 3 * * 0" || true
apply_task_schedule "update_pi_apps.sh" "0 5 * * 0" || true
get_task_status "update_pi_os.sh" "false" || true
get_task_status "update_pi_apps.sh" "false" || true

run_interactive true || true
INSTALL_UI_MODE=text
configure_email_interactive <<< $'n\n' || true
show_email_config || true

# --- Whiptail UI coverage (avoid menu option 0 — it calls exit) ---
export INSTALL_FORCE_TEXT_UI=0
export INSTALL_USE_WHIPTAIL=1
export INSTALL_UI_MODE=whiptail
echo "auto" > "$MOCK_DIR/whiptail_mode"
echo "yes" > "$MOCK_DIR/whiptail_yesno"
: > "$MOCK_DIR/whiptail_input"
: > "$MOCK_DIR/whiptail_checklist"

_open_wizard_ui_fd || true
_has_open_wizard_ui_fds || true
_can_open_wizard_ui_tty || true
INSTALL_FAKE_NO_TTY=1 _can_open_wizard_ui_tty || true
INSTALL_FAKE_NO_TTY=1 _open_wizard_ui_fd || true
_close_wizard_ui_fds || true

can_use_whiptail || true
select_ui_mode || true

printf '%s\n' "whip@test.com" "apppassword" > "$MOCK_DIR/whiptail_input"
configure_email_whiptail || true
show_email_config_whiptail || true
show_email_config || true

echo "0 3 * * 0 $INSTALL_DIR/update_pi_os.sh >/dev/null" > "$MOCK_DIR/root_cron"
printf '%s\n' "disable" > "$MOCK_DIR/whiptail_input"
toggle_task_whiptail 1 || true

echo "0 1 * * 0 $INSTALL_DIR/update_self.sh" > "$MOCK_DIR/root_cron"
echo "0 5 * * 0 $INSTALL_DIR/update_pi_apps.sh >/dev/null" > "$MOCK_DIR/user_cron"
quiet_suite_cron_jobs || true
apply_task_schedule update_pi_os.sh "0 3 * * 0" || true

# Cover INSTALL_DIR/lib fallback when installer tree has no lib/
_INSTALL_ROOT="/tmp/no-install-root-cov-$$"
_install_lib_root || true
_source_install_libs || true
_save_idir=$INSTALL_DIR
INSTALL_DIR="/tmp/no-pi-scripts-cov-$$"
_install_lib_root || true
_source_install_libs || true
INSTALL_DIR=$_save_idir
_require_update_helpers || true
unset -f pkg_install has_mail_sender
_require_update_helpers || true
is_installed() { command -v "$1" > /dev/null 2>&1; }
# shellcheck source=../../lib/os_pkg.sh
source ./lib/os_pkg.sh
# shellcheck source=../../lib/mail_send.sh
source ./lib/mail_send.sh
_install_atomic_copy "/no/such/src" "$INSTALL_DIR/atomic_copy_fail" || true
_install_atomic_curl "file:///no/such/rpi-atomic-curl-missing" "$INSTALL_DIR/atomic_curl_fail" || true

echo "0 3 * * 0 $INSTALL_DIR/update_pi_os.sh >/dev/null" > "$MOCK_DIR/root_cron"
printf '%s\n' "edit" "0 1 * * 0" > "$MOCK_DIR/whiptail_input"
toggle_task_whiptail 1 || true

: > "$MOCK_DIR/root_cron"
echo "yes" > "$MOCK_DIR/whiptail_yesno"
printf '%s\n' "0 4 * * 0" > "$MOCK_DIR/whiptail_input"
toggle_task_whiptail 1 || true

echo "no" > "$MOCK_DIR/whiptail_yesno"
toggle_task_whiptail 1 || true

echo "cancel" > "$MOCK_DIR/whiptail_mode"
toggle_task_whiptail 1 || true
echo "auto" > "$MOCK_DIR/whiptail_mode"
echo "yes" > "$MOCK_DIR/whiptail_yesno"

_confirm_reboot_tasks_whiptail || true
echo "no" > "$MOCK_DIR/whiptail_yesno"
_confirm_reboot_tasks_whiptail || true
echo "yes" > "$MOCK_DIR/whiptail_yesno"

printf '%s\n' "1" "back" > "$MOCK_DIR/whiptail_input"
manage_tasks_ui_whiptail || true

# Avoid stubbing menus away — option 0 now returns instead of exiting.
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/lib"
cp -a lib/*.sh "$INSTALL_DIR/lib/" 2> /dev/null || true
printf '%s\n' "fresh@test.com" "apppassword" > "$MOCK_DIR/whiptail_input"
printf '%s\n' "1" "7" > "$MOCK_DIR/whiptail_checklist"
# After wizard, main_menu_whiptail opens — drive a few options then exit.
{
    printf '%s\n' "fresh@test.com" "apppassword"
    printf '%s\n' "2" "4" "5" "0"
} > "$MOCK_DIR/whiptail_input"
printf '%s\n' "1" "7" > "$MOCK_DIR/whiptail_checklist"
echo "yes" > "$MOCK_DIR/whiptail_yesno"
run_fresh_install_whiptail || true

INSTALL_UI_MODE=text
INSTALL_FORCE_TEXT_UI=1
INSTALL_USE_WHIPTAIL=0
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib"
cp -a lib/*.sh "$INSTALL_DIR/lib/" 2> /dev/null || true
printf 'n\ntest@x.com\npass\nY\nn\nn\nn\nn\nn\nn\nn\n0\n' | run_fresh_install_text || true

# Dependency failure warnings
pkg_install() { return 1; }
has_mail_sender() { return 1; }
is_installed() { return 1; }
check_dependencies || true
unset -f pkg_install is_installed has_mail_sender
is_installed() { command -v "$1" > /dev/null 2>&1; }
# shellcheck source=../../lib/os_pkg.sh
source ./lib/os_pkg.sh
# shellcheck source=../../lib/mail_send.sh
source ./lib/mail_send.sh

install_main --update || true

# Full whiptail main menu coverage
mkdir -p "$INSTALL_DIR"
INSTALL_UI_MODE=whiptail
INSTALL_USE_WHIPTAIL=1
INSTALL_FORCE_TEXT_UI=0
echo "auto" > "$MOCK_DIR/whiptail_mode"
_start_uninstall() {
    echo "UNINSTALL_STUB"
    return 0
}
printf '%s\n' "1" "menu@test.com" "secretpass" "2" "3" "1" "0" "6" "0" > "$MOCK_DIR/whiptail_input"
echo "yes" > "$MOCK_DIR/whiptail_yesno"
main_menu_whiptail || true
echo "no" > "$MOCK_DIR/whiptail_yesno"
printf '%s\n' "6" "0" > "$MOCK_DIR/whiptail_input"
main_menu_whiptail || true
echo "cancel" > "$MOCK_DIR/whiptail_mode"
main_menu_whiptail || true
echo "auto" > "$MOCK_DIR/whiptail_mode"
: > "$MOCK_DIR/whiptail_input"
main_menu_whiptail || true

# show_email_config dispatcher with whiptail then fallback
INSTALL_UI_MODE=whiptail
show_email_config || true
echo "fail" > "$MOCK_DIR/whiptail_mode"
show_email_config || true
echo "auto" > "$MOCK_DIR/whiptail_mode"

# Invalid email / empty password whiptail paths
printf '%s\n' "bad-email" > "$MOCK_DIR/whiptail_input"
configure_email_whiptail || true
printf '%s\n' "ok@test.com" "" > "$MOCK_DIR/whiptail_input"
configure_email_whiptail || true
echo "cancel" > "$MOCK_DIR/whiptail_mode"
configure_email_whiptail || true
echo "auto" > "$MOCK_DIR/whiptail_mode"

INSTALL_UI_MODE=whiptail
main_menu || true

echo "install coverage driver done"
exit 0
