#!/usr/bin/env bats

# Tests for uninstall.sh

setup() {
    export MOCK_DIR="/tmp/mocks"
    # Never let uninstall tests delete a real ~/pi-scripts on the host.
    export LEGACY_INSTALL_DIR="/tmp/pi-scripts-legacy-isolated"
    export INSTALL_DIR="/tmp/scripts" # Matches default mock
    
    # Always ensure clean shared mocks
    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"
    
    # Create mock install directory
    mkdir -p "$INSTALL_DIR"
    touch "$INSTALL_DIR/update_pi_os.sh"
    touch "$INSTALL_DIR/update_pi_apps.sh"
    echo "v0.0.0" > "$INSTALL_DIR/.version"
    export TEST_MODE="true"
    chmod +x ./uninstall.sh
    
    # Unmock grep to avoid wrapper issues with regex
    rm -f "$MOCK_DIR/grep"
}

@test "Uninstall: Removes scripts directory" {
    run bash ./uninstall.sh
    
    # Verify post-condition
    [ ! -d "$INSTALL_DIR" ]
    [[ "$output" =~ "Removing scripts from" ]]
    [[ "$output" =~ "Uninstallation complete" ]]
}

@test "Uninstall: Handles missing directory gracefully" {
    rm -rf "$INSTALL_DIR"
    
    run bash ./uninstall.sh
    
    [[ "$output" =~ "Installation directory" ]]
    [[ "$output" =~ "not currently installed" ]] || [[ "$output" =~ "not found" ]]
    [[ "$output" =~ "Uninstallation complete" ]]
}

@test "Uninstall: Cleans crontabs (Mocked)" {
    # Mock crontab to return some content
    # We need to verify that 'crontab -' (write) is called with filtered content
    
    # Setup mock crontab behaviour:
    # If -l is passed, cat a mock file.
    # If - (stdin) is passed (via piped grep), capture it.
    
    cat << 'EOF' > "$MOCK_DIR/crontab"
#!/bin/bash
if [[ "$*" == *"-l"* ]]; then
    if [ "$IS_MOCKED_SUDO" == "true" ]; then
        # Root Crontab Entries
        echo 'MAILTO="test@test.com"'
        echo "0 0 * * * /tmp/scripts/update_pi_os.sh"
        echo "0 1 * * * /tmp/scripts/update_pi_firmware.sh"
        echo "0 2 * * * /usr/bin/root_job"
    else
        # User Crontab Entries
        echo 'MAILTO="test@test.com"'
        echo "0 5 * * * /tmp/scripts/update_pi_apps.sh"
        echo "0 6 * * * /usr/bin/user_job"
    fi
else
    # Writing to crontab - append to file for verification
    if [ "$IS_MOCKED_SUDO" == "true" ]; then
        echo "--- ROOT CRON WRITE ---" >> "/tmp/mocks/crontab_written"
    else
        echo "--- USER CRON WRITE ---" >> "/tmp/mocks/crontab_written"
    fi
    if [[ -f "$1" ]]; then
        cat "$1" >> "/tmp/mocks/crontab_written"
    else
        cat >> "/tmp/mocks/crontab_written"
    fi
fi
EOF
    chmod +x "$MOCK_DIR/crontab"
    
    run bash ./uninstall.sh
    echo "UNINSTALL OUTPUT: $output"
    
    # Verify output shows "Cleaning up crontabs"
    [[ "$output" =~ "Cleaning up crontabs" ]]
    
    # Check what was written. Should NOT contain our scripts, SHOULD contain 'root_job' and 'user_job'
    if [ -f "/tmp/mocks/crontab_written" ]; then
        run cat "/tmp/mocks/crontab_written"
        
        # Verify Root Section
        [[ "$output" =~ "root_job" ]]
        [[ "$output" != *"update_pi_os.sh"* ]]
        [[ "$output" != *"MAILTO="* ]]
        
        # Verify User Section
        [[ "$output" =~ "user_job" ]]
        [[ "$output" != *"update_pi_apps.sh"* ]]
        [[ "$output" != *"MAILTO="* ]]
    fi
}

@test "Uninstall: Entry Point (Direct Execution)" {
    # This tests the "if [[ -z ... ]]" block at the end
    # We rely on the fact that running it via BATS 'run' executes it as a script, 
    # but we need to ensure the logic triggers 'main'
    
    run bash ./uninstall.sh
    [[ "$output" =~ "RPi Maintenance Suite Uninstaller" ]]
}
@test "Uninstall: Detects INSTALL_DIR from Crontab" {
    # Move scripts to a custom location
    CUSTOM_DIR="/tmp/custom_pi_scripts"
    mkdir -p "$CUSTOM_DIR"
    touch "$CUSTOM_DIR/update_pi_os.sh"
    echo "v0.0.0" > "$CUSTOM_DIR/.version"
    
    # Set default INSTALL_DIR to something non-existent
    export INSTALL_DIR="/tmp/non_existent_default"
    
    # Mock root crontab to have the custom path
    # We must mock sudo crontab -l since the script uses it
    cat << EOF > "$MOCK_DIR/crontab"
#!/bin/bash
if [[ "\$*" == *"-l"* ]]; then
    echo "0 0 * * * $CUSTOM_DIR/update_pi_os.sh"
fi
EOF
    chmod +x "$MOCK_DIR/crontab"
    
    run bash ./uninstall.sh
    
    [[ "$output" =~ "Detected installation directory: $CUSTOM_DIR" ]]
    [[ "$output" =~ "Removing scripts from $CUSTOM_DIR" ]]
    [ ! -d "$CUSTOM_DIR" ]
    
    # Cleanup
    rm -rf "$CUSTOM_DIR"
}
@test "Uninstall: Detects INSTALL_DIR from User Crontab" {
    # Move scripts to a custom location
    CUSTOM_DIR="/tmp/custom_pi_scripts_user"
    mkdir -p "$CUSTOM_DIR"
    touch "$CUSTOM_DIR/update_pi_apps.sh"
    echo "v0.0.0" > "$CUSTOM_DIR/.version"
    
    # Set default INSTALL_DIR to something non-existent
    export INSTALL_DIR="/tmp/non_existent_default"
    
    # Mock user crontab (no sudo)
    cat << EOF > "$MOCK_DIR/crontab"
#!/bin/bash
if [[ "\$*" == *"-l"* ]] && [[ "\$IS_MOCKED_SUDO" != "true" ]]; then
    echo "0 0 * * * $CUSTOM_DIR/update_pi_apps.sh"
fi
EOF
    chmod +x "$MOCK_DIR/crontab"
    
    run bash ./uninstall.sh
    
    [[ "$output" =~ "Detected installation directory: $CUSTOM_DIR" ]]
    [ ! -d "$CUSTOM_DIR" ]
    
    # Cleanup
    rm -rf "$CUSTOM_DIR"
}

@test "Uninstall: No crontab changes needed" {
    # Mock crontab with unrelated entries
    cat << EOF > "$MOCK_DIR/crontab"
#!/bin/bash
if [[ "\$*" == *"-l"* ]]; then
    echo "0 0 * * * /usr/bin/unrelated_job"
fi
EOF
    chmod +x "$MOCK_DIR/crontab"
    
    run bash ./uninstall.sh
    
    # Should NOT say "Root crontab updated"
    [[ ! "$output" =~ "Root crontab updated" ]]
    [[ "$output" =~ "Cleaning up crontabs" ]]
}

@test "Uninstall: run_interactive coverage" {
    # Exercise the non-test-mode branches of run_interactive
    run bash -c "export TEST_MODE=false; source ./uninstall.sh; run_interactive echo 'test_interactive'"
    [[ "$output" =~ "test_interactive" ]]
}

@test "Uninstall: prefers INSTALL_DIR ui_msg helpers" {
    local tmp root
    tmp=$(mktemp -d)
    root=$(mktemp -d)
    mkdir -p "$tmp/lib" "$root"
    cp ./lib/ui_msg.sh "$tmp/lib/"
    run bash -c "
        export PI_UNINSTALL_ROOT_OVERRIDE='$root'
        export INSTALL_DIR='$tmp'
        export TEST_MODE=true
        source ./uninstall.sh
        printf '%s\n' \"\$(_pi_gettextf 'Hello %s' 'world')\"
        _pi_echof 'Bye %s' 'now'
    "
    [[ "$output" =~ "Hello world" ]]
    [[ "$output" =~ "Bye now" ]]
    rm -rf "$tmp" "$root"
}

@test "Uninstall: inline stubs when ui_msg missing" {
    local tmp root
    tmp=$(mktemp -d)
    root=$(mktemp -d)
    mkdir -p "$tmp" "$root"
    run bash -c "
        export PI_UNINSTALL_ROOT_OVERRIDE='$root'
        export INSTALL_DIR='$tmp'
        export TEST_MODE=true
        source ./uninstall.sh
        printf '%s\n' \"\$(_pi_gettext 'plain')\"
        printf '%s\n' \"\$(_pi_gettextf 'Hi %s' 'there')\"
        _pi_echo 'line'
        _pi_echof 'Fmt %s' 'x'
    "
    [[ "$output" =~ "plain" ]]
    [[ "$output" =~ "Hi there" ]]
    [[ "$output" =~ "line" ]]
    [[ "$output" =~ "Fmt x" ]]
    rm -rf "$tmp" "$root"
}

@test "Uninstall: mktemp failure aborts crontab cleanup" {
    run bash -c '
        export TEST_MODE=true PATH='"$MOCK_DIR"':$PATH INSTALL_DIR='"$INSTALL_DIR"'
        mktemp() { return 1; }
        export -f mktemp
        source ./uninstall.sh
        main
        echo RC=$?
    '
    [[ "$output" =~ "RC=1" ]]
}

@test "Uninstall: removes a root-owned install tree via sudo" {
    sudo -n true 2> /dev/null || skip "passwordless sudo required"
    local parent="/tmp/pi-scripts-uninstall-rootowned"
    sudo -n rm -rf "$parent"
    sudo -n /usr/bin/install -d -o root -g root -m 0755 "$parent" "$parent/tree"
    sudo -n /usr/bin/install -o root -g root -m 0755 ./scripts/update_pi_os.sh "$parent/tree/update_pi_os.sh"
    sudo -n /usr/bin/install -o root -g root -m 0644 ./VERSION "$parent/tree/.version"
    export INSTALL_DIR="$parent/tree"

    run bash ./uninstall.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Removing scripts from $INSTALL_DIR" ]]
    [ ! -d "$INSTALL_DIR" ]
    sudo -n rm -rf "$parent"
}

@test "Uninstall: also removes a legacy user-writable tree" {
    export LEGACY_INSTALL_DIR="/tmp/pi-scripts-uninstall-legacy"
    mkdir -p "$LEGACY_INSTALL_DIR/lib"
    # Full installer layout: all seven scripts, the three helper libs, marker and staging leftovers.
    touch "$LEGACY_INSTALL_DIR"/{update_pi_os,update_pi_firmware,update_pip,update_pi_apps}.sh
    touch "$LEGACY_INSTALL_DIR"/{docker_cleanup,update_samsung_ssd,update_self}.sh
    touch "$LEGACY_INSTALL_DIR"/lib/{os_pkg,mail_send,ui_msg}.sh "$LEGACY_INSTALL_DIR/lib/.rpi-install.x"
    touch "$LEGACY_INSTALL_DIR/.rpi-install.y" "$LEGACY_INSTALL_DIR/update_pi_os.sh.rpi-new.1"
    echo "v0.0.0" > "$LEGACY_INSTALL_DIR/.version"

    run bash ./uninstall.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Removing legacy scripts from $LEGACY_INSTALL_DIR" ]]
    [ ! -d "$LEGACY_INSTALL_DIR" ]
    [ ! -d "$INSTALL_DIR" ]
}

@test "Uninstall: default INSTALL_DIR is the root-owned tree" {
    export INSTALL_DIR="/tmp/pi-scripts-uninstall-default-probe"
    rm -rf "$INSTALL_DIR"
    run env -u INSTALL_DIR bash -c "source ./uninstall.sh; printf '%s' \"\$DEFAULT_INSTALL_DIR\""
    [ "$output" = "/usr/local/lib/pi-maintenance" ]
}

@test "Uninstall: detection uses the crontab captured before entries are stripped" {
    CUSTOM_DIR="/tmp/custom_pi_scripts_once"
    mkdir -p "$CUSTOM_DIR"
    touch "$CUSTOM_DIR/update_pi_os.sh"
    echo "v0.0.0" > "$CUSTOM_DIR/.version"
    export INSTALL_DIR="/tmp/non_existent_default"
    # Stateful mock: the entry disappears after the first write, and the line ends in a redirect.
    echo "0 0 * * * $CUSTOM_DIR/update_pi_os.sh >/dev/null 2>&1" > "$MOCK_DIR/root_cron"
    rm -f "$MOCK_DIR/user_cron"

    run bash ./uninstall.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Detected installation directory: $CUSTOM_DIR" ]]
    [ ! -d "$CUSTOM_DIR" ]
}

@test "Uninstall: refuses to delete a detected directory holding non-suite files" {
    HOME_LIKE="/tmp/custom_pi_home_like"
    mkdir -p "$HOME_LIKE"
    touch "$HOME_LIKE/update_pi_os.sh"
    echo "thesis" > "$HOME_LIKE/thesis.txt"
    export INSTALL_DIR="/tmp/non_existent_default"
    echo "0 0 * * * $HOME_LIKE/update_pi_os.sh >/dev/null 2>&1" > "$MOCK_DIR/root_cron"
    rm -f "$MOCK_DIR/user_cron"

    run bash ./uninstall.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Refusing to remove $HOME_LIKE" ]]
    [ -f "$HOME_LIKE/thesis.txt" ]
    rm -rf "$HOME_LIKE"
}

@test "Uninstall: refuses to delete a legacy tree holding non-suite files" {
    export LEGACY_INSTALL_DIR="/tmp/pi-scripts-uninstall-legacy-data"
    mkdir -p "$LEGACY_INSTALL_DIR/lib"
    touch "$LEGACY_INSTALL_DIR/update_pi_os.sh" "$LEGACY_INSTALL_DIR/lib/os_pkg.sh"
    echo "photos" > "$LEGACY_INSTALL_DIR/lib/backup.tar"

    run bash ./uninstall.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Refusing to remove legacy $LEGACY_INSTALL_DIR" ]]
    [ -f "$LEGACY_INSTALL_DIR/lib/backup.tar" ]
    rm -rf "$LEGACY_INSTALL_DIR"
}

@test "Uninstall: refuses to delete a directory without the .version marker" {
    rm -f "$INSTALL_DIR/.version"
    run bash ./uninstall.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Refusing to remove $INSTALL_DIR" ]]
    [ -f "$INSTALL_DIR/update_pi_os.sh" ]
}

@test "Uninstall: detects the directory from any scheduled suite script" {
    CUSTOM_DIR="/tmp/custom_pi_scripts_self"
    mkdir -p "$CUSTOM_DIR"
    touch "$CUSTOM_DIR/update_self.sh"
    echo "v0.0.0" > "$CUSTOM_DIR/.version"
    export INSTALL_DIR="/tmp/non_existent_default"
    echo "0 1 * * 0 $CUSTOM_DIR/update_self.sh >/dev/null 2>&1" > "$MOCK_DIR/root_cron"
    rm -f "$MOCK_DIR/user_cron"

    run bash ./uninstall.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Detected installation directory: $CUSTOM_DIR" ]]
    [ ! -d "$CUSTOM_DIR" ]
}
