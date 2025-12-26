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
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; export RAW_URL='http://mock'; source ./install.sh; main_menu <<< $'5\ny'"
    
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
