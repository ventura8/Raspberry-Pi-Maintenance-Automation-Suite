#!/usr/bin/env bats

# Additional coverage tests for install.sh

setup() {
    export MOCK_DIR="/tmp/mocks"
    export INSTALL_DIR="/tmp/scripts_boost"
    rm -rf "$INSTALL_DIR"
    export SSMTP_CONF="/tmp/ssmtp_boost.conf"
    export REVALIASES="/tmp/revaliases_boost"
    
    # Always ensure clean shared mocks
    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"
    export TEST_MODE="true"
    unset INSTALL_USE_WHIPTAIL || true
    export INSTALL_FORCE_TEXT_UI="0"
    export INSTALL_UI_MODE=""
}

@test "Install: Manage Tasks UI - Return to Menu" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; manage_tasks_ui <<< '0'"
    [[ "$output" =~ "Enter ID to toggle" ]]
}

@test "Install: Manage Tasks UI - Invalid ID" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; manage_tasks_ui <<< $'99\n0'"
    [[ "$output" =~ "Enter ID to toggle" ]]
}

@test "Install: Toggle Task - User Cron (Pi-Apps Enable)" {
    rm -f "$MOCK_DIR/user_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 5 <<< $'y\n0 6 * * *'"
    [[ "$output" =~ "Pi-Apps Update" ]]
    [[ "$output" =~ "Task enabled" ]]
}

@test "Install: Show Email Config - Missing File" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; SSMTP_CONF=\"/tmp/nonexistent_ssmtp\"; show_email_config <<< ''"
    [[ "$output" =~ "No SSMTP configuration found" ]]
}

@test "Install: Download Scripts - All Success" {
    # Scripts should ALREADY be present if mocked correctly or we can touch them
    mkdir -p "$INSTALL_DIR"
    run bash -c "export PATH=$MOCK_DIR:$PATH; export INSTALL_DIR=$INSTALL_DIR; source ./install.sh; download_scripts"
    [[ "$output" =~ "Scripts updated" ]]
}

@test "Install: Main Menu - View Email Config (Missing)" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; SSMTP_CONF=\"/tmp/nonexistent_ssmtp\"; main_menu <<< $'2\n\n0'"
    [[ "$output" =~ "No SSMTP configuration found" ]]
}

@test "Install: Main Menu - Manage Tasks" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'3\n0\n0'"
    [[ "$output" =~ "Task Status Manager" ]]
}

@test "Install: Cron to Human - Invalid Day" {
    run bash -c "source ./install.sh; cron_to_human '0 0 * * 8'"
    [[ "$output" =~ "Dow 8" ]]
}

@test "Install: Manage Tasks UI - Toggle Task 1" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; manage_tasks_ui <<< $'1\ny\n\n0'"
    [[ "$output" =~ "Task: System OS Update" ]]
}

@test "Install: Main Menu - Uninstall Flow" {
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
echo 'echo "MOCK_UNINSTALL"'
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"
    
    TD=$(mktemp -d)
    cp ./install.sh "$TD/"
    cd "$TD"
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; export RAW_URL='http://mock'; source ./install.sh; main_menu <<< $'6\ny'"
    
    cd - > /dev/null
    rm -rf "$TD"
    
    [[ "$output" =~ "MOCK_UNINSTALL" ]]
}

@test "Install: Entry Point - Manage Mode" {
    mkdir -p "/tmp/pi-scripts-test"
    cp ./install.sh /tmp/install_temp_manage.sh
    sed -i 's/main_menu/exit 0 #/' /tmp/install_temp_manage.sh
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; export INSTALL_DIR='/tmp/pi-scripts-test'; /tmp/install_temp_manage.sh <<< '0'"
    
    rm -f /tmp/install_temp_manage.sh
    rm -rf /tmp/pi-scripts-test
}

@test "Install: Entry Point - Fresh Mode" {
    rm -rf "/tmp/pi-scripts-fresh"
    cp ./install.sh /tmp/install_temp_fresh.sh
    sed -i 's/run_fresh_install/exit 0 #/' /tmp/install_temp_fresh.sh
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; export INSTALL_DIR='/tmp/pi-scripts-fresh'; /tmp/install_temp_fresh.sh <<< '0'"
    
    rm -f /tmp/install_temp_fresh.sh
}
@test "Install: Download Scripts - VERSION unavailable" {
    # Source a copy under MOCK_DIR so repo-root VERSION is not visible; curl fails.
    CUT_LINE=$(grep -n "# --- Entry Point ---" ./install.sh | head -n 1 | cut -d: -f1)
    head -n "$((CUT_LINE - 1))" ./install.sh > "$MOCK_DIR/install_lib_nover.sh"
    rm -f "$MOCK_DIR/VERSION"

    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"

    mkdir -p "$INSTALL_DIR"
    run bash -c "export PATH=$MOCK_DIR:$PATH; export INSTALL_DIR=$INSTALL_DIR; source \"$MOCK_DIR/install_lib_nover.sh\"; download_scripts"
    [[ "$output" =~ "Scripts updated" ]]
    [[ "$output" =~ "could not read VERSION" ]]
    [[ ! -f "$INSTALL_DIR/.version" ]]
}

@test "Install: Entry Point - Non-Interactive Update" {
    # Test the --update flag with libs only under INSTALL_DIR (parent-dir installer layout).
    mkdir -p "$INSTALL_DIR/lib"
    cp ./lib/*.sh "$INSTALL_DIR/lib/"

    # Temp copy under BATS tmp (never write into bind-mounted repo root).
    local tmp_install="${BATS_TEST_TMPDIR:-/tmp}/install_tmp.sh"
    cp ./install.sh "$tmp_install"
    # Mock download_scripts to avoid real network (call site only).
    sed -i 's/^        download_scripts$/        echo "MOCKED_DOWNLOAD"/' "$tmp_install"

    run bash "$tmp_install" --update

    rm -f "$tmp_install"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "MOCKED_DOWNLOAD" ]]
    [[ ! "$output" =~ "command not found" ]]
}

@test "Install: --update fails closed when package helpers are missing" {
    local isolated="${BATS_TEST_TMPDIR:-/tmp}/iso_nolib"
    rm -rf "$isolated"
    mkdir -p "$isolated" "$INSTALL_DIR"
    # Ensure no installed lib fallback and no network bootstrap.
    rm -rf "$INSTALL_DIR/lib"
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
exit 22
EOF
    chmod +x "$MOCK_DIR/curl"
    cp ./install.sh "$isolated/install.sh"
    run bash -c "export PATH=$MOCK_DIR:\$PATH INSTALL_DIR=$INSTALL_DIR; bash \"$isolated/install.sh\" --update"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "package helpers not loaded" ]]
}

@test "Install: apply_task_schedule redirects stdout and stderr" {
    : > "$MOCK_DIR/root_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; apply_task_schedule update_pi_os.sh '0 3 * * 0'"
    [[ "$status" -eq 0 ]]
    grep -q 'update_pi_os.sh >/dev/null 2>&1' "$MOCK_DIR/root_cron"
}

@test "Install: quiet_suite_cron_jobs rewrites lines without redirect" {
    echo "0 1 * * 0 $INSTALL_DIR/update_self.sh" > "$MOCK_DIR/root_cron"
    echo "0 5 * * 0 $INSTALL_DIR/update_pi_apps.sh >/dev/null" > "$MOCK_DIR/user_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; quiet_suite_cron_jobs"
    [[ "$status" -eq 0 ]]
    grep -q 'update_self.sh >/dev/null 2>&1' "$MOCK_DIR/root_cron"
    grep -q 'update_pi_apps.sh >/dev/null 2>&1' "$MOCK_DIR/user_cron"
}

@test "Install: quiet_suite_cron_jobs preserves @daily macro schedules" {
    echo "@daily $INSTALL_DIR/update_self.sh" > "$MOCK_DIR/root_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; quiet_suite_cron_jobs"
    [[ "$status" -eq 0 ]]
    grep -qE '^@daily .*update_self\.sh >/dev/null 2>&1$' "$MOCK_DIR/root_cron"
}

@test "Install: atomic download does not break a running dest script" {
    mkdir -p "$INSTALL_DIR"
    local runner_out="${BATS_TEST_TMPDIR:-/tmp}/atomic_runner.out"
    cat > "$INSTALL_DIR/update_self.sh" << 'EOF'
#!/bin/bash
for i in 1 2 3 4 5; do
    sleep 0.2
done
echo ATOMIC_RUNNER_DONE
EOF
    chmod +x "$INSTALL_DIR/update_self.sh" 2> /dev/null || true
    bash "$INSTALL_DIR/update_self.sh" > "$runner_out" &
    local pid=$!
    sleep 0.15
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; download_scripts"
    local wait_rc=0
    wait "$pid" || wait_rc=$?
    [[ "$wait_rc" -eq 0 ]]
    grep -q ATOMIC_RUNNER_DONE "$runner_out"
}

@test "Install: run_interactive coverage" {
    # Exercise the non-test-mode branches of run_interactive
    run bash -c "export TEST_MODE=false; source ./install.sh; run_interactive echo 'test_interactive'"
    [[ "$output" =~ "test_interactive" ]]
}
