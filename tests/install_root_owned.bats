#!/usr/bin/env bats

# Root-owned install tree + legacy ($HOME/pi-scripts) migration coverage for install.sh.
# Root cron executes the installed scripts, so the login user must not be able to replace them.

setup() {
    export MOCK_DIR="/tmp/mocks"
    export TEST_MODE="true"
    export INSTALL_FORCE_TEXT_UI="1"
    export INSTALL_UI_MODE=""
    unset INSTALL_USE_WHIPTAIL || true
    export SSMTP_CONF="/tmp/ssmtp_rootowned.conf"
    export MSMTP_CONF="/tmp/msmtprc_rootowned.conf"
    export REVALIASES="/tmp/revaliases_rootowned"
    rm -f "$SSMTP_CONF" "$MSMTP_CONF" "$REVALIASES"

    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"

    export INSTALL_DIR="/tmp/pi-scripts-rootowned-target"
    export LEGACY_INSTALL_DIR="/tmp/pi-scripts-rootowned-legacy"
    rm -rf "$INSTALL_DIR" "$LEGACY_INSTALL_DIR"
    : > "$MOCK_DIR/root_cron"
    : > "$MOCK_DIR/user_cron"
}

teardown() {
    rm -rf "$INSTALL_DIR" "$LEGACY_INSTALL_DIR"
    if [ -n "${ROOT_PARENT:-}" ] && [ -d "$ROOT_PARENT" ]; then
        sudo -n /bin/rm -rf "$ROOT_PARENT" 2> /dev/null || true
    fi
}

_env() {
    printf 'PATH=%q SSMTP_CONF=%q MSMTP_CONF=%q REVALIASES=%q INSTALL_DIR=%q LEGACY_INSTALL_DIR=%q' \
        "$MOCK_DIR:$PATH" "$SSMTP_CONF" "$MSMTP_CONF" "$REVALIASES" "$INSTALL_DIR" "$LEGACY_INSTALL_DIR"
}

# Unique root-owned fixture parent (concurrent BATS runs must not share a fixed /tmp path).
_make_root_parent() {
    ROOT_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/pi-scripts-rootowned-parent.XXXXXX")
    export ROOT_PARENT
    sudo -n /usr/bin/install -d -o root -g root -m 0755 "$ROOT_PARENT"
}

_make_legacy_tree() {
    mkdir -p "$LEGACY_INSTALL_DIR/lib"
    cp ./scripts/update_pi_os.sh ./scripts/update_pi_apps.sh "$LEGACY_INSTALL_DIR/"
    cp ./lib/*.sh "$LEGACY_INSTALL_DIR/lib/"
    echo "v0.0.1" > "$LEGACY_INSTALL_DIR/.version"
    echo "0 3 * * 0 $LEGACY_INSTALL_DIR/update_pi_os.sh >/dev/null 2>&1" > "$MOCK_DIR/root_cron"
    echo "0 1 * * 0 $LEGACY_INSTALL_DIR/update_self.sh >/dev/null 2>&1" >> "$MOCK_DIR/root_cron"
    echo "0 5 * * 0 $LEGACY_INSTALL_DIR/update_pi_apps.sh >/dev/null 2>&1" > "$MOCK_DIR/user_cron"
}

@test "Root-owned: default INSTALL_DIR is /usr/local/lib/pi-maintenance" {
    run env -u INSTALL_DIR bash -c "source ./install.sh; printf '%s' \"\$INSTALL_DIR\""
    [ "$status" -eq 0 ]
    [ "$output" = "/usr/local/lib/pi-maintenance" ]
}

@test "Root-owned: legacy \$HOME/pi-scripts INSTALL_DIR is redirected to the default" {
    run env INSTALL_DIR="$HOME/pi-scripts" bash -c "source ./install.sh; printf '%s' \"\$INSTALL_DIR\""
    [ "$status" -eq 0 ]
    [ "$output" = "/usr/local/lib/pi-maintenance" ]
}

@test "Root-owned: explicit INSTALL_DIR override is honoured" {
    run env INSTALL_DIR="/tmp/pi-scripts-custom" bash -c "source ./install.sh; printf '%s' \"\$INSTALL_DIR\""
    [ "$output" = "/tmp/pi-scripts-custom" ]
}

@test "Root-owned: download_scripts into an unwritable parent yields root:root 0755/0644 files" {
    sudo -n true 2> /dev/null || skip "passwordless sudo required"
    _make_root_parent
    export INSTALL_DIR="$ROOT_PARENT/tree"

    run bash -c "export $(_env); source ./install.sh; download_scripts"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Scripts updated" ]]

    [ "$(stat -c %U "$INSTALL_DIR")" = "root" ]
    [ "$(stat -c %a "$INSTALL_DIR")" = "755" ]
    [ "$(stat -c %U:%a "$INSTALL_DIR/update_pi_os.sh")" = "root:755" ]
    [ "$(stat -c %U:%a "$INSTALL_DIR/lib/os_pkg.sh")" = "root:644" ]
    [ "$(stat -c %U:%a "$INSTALL_DIR/.version")" = "root:644" ]
    # No staging leftovers, and nothing writable by the invoking user
    [ -z "$(find "$INSTALL_DIR" -name '*.rpi-new.*')" ]
    [ ! -w "$INSTALL_DIR/update_pi_os.sh" ]
}

@test "Root-owned: save_email_configuration rewrites root-owned scripts via sudo" {
    sudo -n true 2> /dev/null || skip "passwordless sudo required"
    _make_root_parent
    export INSTALL_DIR="$ROOT_PARENT/tree"

    run bash -c "export $(_env); source ./install.sh; download_scripts > /dev/null; save_email_configuration mail@example.com secret"
    [ "$status" -eq 0 ]
    grep -q 'RECIPIENT_EMAIL="mail@example.com"' "$INSTALL_DIR/update_pi_os.sh"
    [ "$(stat -c %U "$INSTALL_DIR/update_pi_os.sh")" = "root" ]
}

@test "Root-owned: user-writable INSTALL_DIR is written directly (no sudo)" {
    cat << 'EOS' > "$MOCK_DIR/sudo"
#!/bin/bash
echo "SUDO_CALLED $*" >&2
exit 1
EOS
    chmod +x "$MOCK_DIR/sudo"
    run bash -c "export $(_env); source ./install.sh; download_scripts"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "SUDO_CALLED install" ]]
    [ -f "$INSTALL_DIR/update_pi_os.sh" ]
    [ -x "$INSTALL_DIR/update_pi_os.sh" ]
    [ "$(stat -c %a "$INSTALL_DIR/lib/mail_send.sh")" = "644" ]
}

@test "Root-owned: --update migrates a legacy tree and repoints both crontabs" {
    _make_legacy_tree
    run bash -c "export $(_env); bash ./install.sh --update"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Removed legacy install directory $LEGACY_INSTALL_DIR" ]]
    [ ! -d "$LEGACY_INSTALL_DIR" ]
    [ -f "$INSTALL_DIR/update_pi_os.sh" ]
    grep -q "^0 3 \* \* 0 $INSTALL_DIR/update_pi_os.sh >/dev/null 2>&1\$" "$MOCK_DIR/root_cron"
    grep -q "^0 1 \* \* 0 $INSTALL_DIR/update_self.sh >/dev/null 2>&1\$" "$MOCK_DIR/root_cron"
    grep -q "^0 5 \* \* 0 $INSTALL_DIR/update_pi_apps.sh >/dev/null 2>&1\$" "$MOCK_DIR/user_cron"
    ! grep -q "$LEGACY_INSTALL_DIR" "$MOCK_DIR/root_cron" "$MOCK_DIR/user_cron"
}

@test "Root-owned: --update with no legacy tree leaves nothing to retire" {
    run bash -c "export $(_env); bash ./install.sh --update"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Removed legacy" ]]
    [ -f "$INSTALL_DIR/.version" ]
}

@test "Root-owned: interactive entry migrates a legacy-only install before the menu" {
    _make_legacy_tree
    local tmp_install="${BATS_TEST_TMPDIR:-/tmp}/install_migrate.sh"
    cp ./install.sh "$tmp_install"
    sed -i 's/^        run_interactive main_menu$/        echo "MENU_REACHED"/' "$tmp_install"

    run bash -c "export $(_env); bash $tmp_install <<< '0'"
    rm -f "$tmp_install"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Migrating scripts to root-owned $INSTALL_DIR" ]]
    [[ "$output" =~ "MENU_REACHED" ]]
    [ ! -d "$LEGACY_INSTALL_DIR" ]
    grep -q "$INSTALL_DIR/update_pi_os.sh" "$MOCK_DIR/root_cron"
}

@test "Root-owned: legacy dir without suite files is repointed but not deleted" {
    mkdir -p "$LEGACY_INSTALL_DIR"
    echo "keep" > "$LEGACY_INSTALL_DIR/notes.txt"
    echo "0 3 * * 0 $LEGACY_INSTALL_DIR/update_pi_os.sh >/dev/null 2>&1" > "$MOCK_DIR/root_cron"
    run bash -c "export $(_env); source ./install.sh; _retire_legacy_install_dirs \"\$(_legacy_install_dirs)\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Left $LEGACY_INSTALL_DIR in place" ]]
    [ -f "$LEGACY_INSTALL_DIR/notes.txt" ]
    grep -q "$INSTALL_DIR/update_pi_os.sh" "$MOCK_DIR/root_cron"
}

@test "Root-owned: a home-like directory holding scripts plus user data is never deleted" {
    # README's manual crontab example points at /home/pi/update_pi_os.sh — the parent is a home dir.
    _make_legacy_tree
    echo "user data" > "$LEGACY_INSTALL_DIR/thesis.txt"
    run bash -c "export $(_env); bash ./install.sh --update"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Left $LEGACY_INSTALL_DIR in place" ]]
    [[ ! "$output" =~ "Removed legacy" ]]
    [ -f "$LEGACY_INSTALL_DIR/thesis.txt" ]
    [ -f "$LEGACY_INSTALL_DIR/update_pi_os.sh" ]
    grep -q "^0 3 \* \* 0 $INSTALL_DIR/update_pi_os.sh >/dev/null 2>&1\$" "$MOCK_DIR/root_cron"
    ! grep -q "$LEGACY_INSTALL_DIR" "$MOCK_DIR/root_cron" "$MOCK_DIR/user_cron"
}

@test "Root-owned: _legacy_dir_is_suite_only accepts the installer layout only" {
    _make_legacy_tree
    touch "$LEGACY_INSTALL_DIR/.rpi-install.abc123" "$LEGACY_INSTALL_DIR/update_self.sh"
    run bash -c "export $(_env); source ./install.sh; _legacy_dir_is_suite_only \"$LEGACY_INSTALL_DIR\""
    [ "$status" -eq 0 ]
    rm -f "$LEGACY_INSTALL_DIR/.version"
    run bash -c "export $(_env); source ./install.sh; _legacy_dir_is_suite_only \"$LEGACY_INSTALL_DIR\""
    [ "$status" -ne 0 ]
}

@test "Root-owned: _legacy_install_dirs ignores INSTALL_DIR and dedupes" {
    _make_legacy_tree
    echo "0 4 * * 0 $INSTALL_DIR/docker_cleanup.sh >/dev/null 2>&1" >> "$MOCK_DIR/root_cron"
    run bash -c "export $(_env); source ./install.sh; _legacy_install_dirs"
    [ "$status" -eq 0 ]
    [ "$output" = "$LEGACY_INSTALL_DIR" ]
}

@test "Root-owned: get_task_status reads the schedule from a legacy-path line" {
    echo "0 3 * * 0 $LEGACY_INSTALL_DIR/update_pi_os.sh >/dev/null 2>&1" > "$MOCK_DIR/root_cron"
    run bash -c "export $(_env); source ./install.sh; get_task_status update_pi_os.sh true"
    [ "$output" = "ENABLED|0 3 * * 0" ]
}

@test "Root-owned: a legacy tree whose parent is unwritable is removed via sudo" {
    sudo -n true 2> /dev/null || skip "passwordless sudo required"
    _make_root_parent
    export LEGACY_INSTALL_DIR="$ROOT_PARENT/legacy"
    sudo -n /usr/bin/install -d -o root -g root -m 0755 "$LEGACY_INSTALL_DIR"
    sudo -n /usr/bin/install -o root -g root -m 0644 ./VERSION "$LEGACY_INSTALL_DIR/.version"
    echo "0 3 * * 0 $LEGACY_INSTALL_DIR/update_pi_os.sh >/dev/null 2>&1" > "$MOCK_DIR/root_cron"

    run bash -c "export $(_env); bash ./install.sh --update"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Removed legacy install directory $LEGACY_INSTALL_DIR" ]]
    [ ! -d "$LEGACY_INSTALL_DIR" ]
}

@test "Root-owned: a failed legacy removal is reported as a warning" {
    _make_legacy_tree
    # Shadow rm with a no-op so the (writable) tree survives the delete attempt.
    printf '#!/bin/bash\nexit 0\n' > "$MOCK_DIR/rm"
    /bin/chmod +x "$MOCK_DIR/rm"
    run bash -c "export $(_env); source ./install.sh; _retire_legacy_install_dirs \"$LEGACY_INSTALL_DIR\""
    /bin/rm -f "$MOCK_DIR/rm"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: could not remove legacy install directory $LEGACY_INSTALL_DIR" ]]
    [ -d "$LEGACY_INSTALL_DIR" ]
}

@test "Root-owned: legacy lib/ holding non-suite files blocks deletion" {
    _make_legacy_tree
    echo "mine" > "$LEGACY_INSTALL_DIR/lib/notes"
    run bash -c "export $(_env); bash ./install.sh --update"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Left $LEGACY_INSTALL_DIR in place" ]]
    [ -f "$LEGACY_INSTALL_DIR/lib/notes" ]
    grep -q "$INSTALL_DIR/update_pi_os.sh" "$MOCK_DIR/root_cron"
}

@test "Root-owned: --update aborts before touching crontabs when the download fails" {
    _make_legacy_tree
    cat << 'EOS' > "$MOCK_DIR/curl"
#!/bin/bash
exit 22
EOS
    /bin/chmod +x "$MOCK_DIR/curl"
    run bash -c "export $(_env); bash ./install.sh --update"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Update incomplete" ]]
    [ -d "$LEGACY_INSTALL_DIR" ]
    grep -q "$LEGACY_INSTALL_DIR/update_pi_os.sh" "$MOCK_DIR/root_cron"
    grep -q "$LEGACY_INSTALL_DIR/update_pi_apps.sh" "$MOCK_DIR/user_cron"
}

@test "Root-owned: interactive migration aborts when the download fails" {
    _make_legacy_tree
    cat << 'EOS' > "$MOCK_DIR/curl"
#!/bin/bash
exit 22
EOS
    /bin/chmod +x "$MOCK_DIR/curl"
    run bash -c "export $(_env); source ./install.sh; migrate_legacy_install"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Migration aborted" ]]
    [ -d "$LEGACY_INSTALL_DIR" ]
    grep -q "$LEGACY_INSTALL_DIR/update_pi_os.sh" "$MOCK_DIR/root_cron"
}

@test "Root-owned: legacy tree is kept when a crontab still references it after repointing" {
    _make_legacy_tree
    # crontab writes are silently dropped: reads keep returning the legacy path.
    cat << EOS > "$MOCK_DIR/crontab"
#!/bin/bash
if [ "\$1" = "-l" ]; then echo "0 3 * * 0 $LEGACY_INSTALL_DIR/update_pi_os.sh >/dev/null 2>&1"; fi
exit 0
EOS
    /bin/chmod +x "$MOCK_DIR/crontab"
    run bash -c "export $(_env); source ./install.sh; _retire_legacy_install_dirs \"$LEGACY_INSTALL_DIR\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "crontab entries still reference $LEGACY_INSTALL_DIR" ]]
    [ -d "$LEGACY_INSTALL_DIR" ]
}

@test "Root-owned: download_scripts fails when the tree cannot be created" {
    export INSTALL_DIR="/proc/pi-scripts-impossible"
    cat << 'EOS' > "$MOCK_DIR/sudo"
#!/bin/bash
exit 1
EOS
    /bin/chmod +x "$MOCK_DIR/sudo"
    run bash -c "export $(_env); source ./install.sh; download_scripts"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "cannot create /proc/pi-scripts-impossible" ]]
}
