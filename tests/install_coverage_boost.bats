#!/usr/bin/env bats

# Additional coverage tests for install.sh

setup() {
    export INSTALL_DIR="./scripts"
    MOCK_DIR="$HOME/mocks"
    mkdir -p "$MOCK_DIR"
    
    # Basic mocks
    cat << 'EOF' > "$MOCK_DIR/sudo"
#!/bin/bash
while [[ "$1" == -* ]]; do shift; done
"$@"
EOF
    chmod +x "$MOCK_DIR/sudo"

    cat << 'EOF' > "$MOCK_DIR/crontab"
#!/bin/bash
if [[ "$*" == *"-l"* ]]; then
    if [ -f "/tmp/mock_crontab" ]; then
        cat "/tmp/mock_crontab"
    else
        echo ""
    fi
else
    cat > /tmp/mock_crontab
fi
EOF
    chmod +x "$MOCK_DIR/crontab"

    for cmd in tee chown chmod usermod sed; do
        echo "#!/bin/bash" > "$MOCK_DIR/$cmd"
        chmod +x "$MOCK_DIR/$cmd"
    done
}

@test "Install: Manage Tasks UI - Return to Menu" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; manage_tasks_ui <<< '0'"
    [[ "$output" =~ "Enter ID to toggle" ]]
}

@test "Install: Manage Tasks UI - Invalid ID" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; manage_tasks_ui <<< $'99\\n0'"
    [[ "$output" =~ "Enter ID to toggle" ]]
}

@test "Install: Toggle Task - User Cron (Pi-Apps Enable)" {
    rm -f /tmp/mock_crontab
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 5 <<< $'y\\n0 6 * * *'"
    [[ "$output" =~ "Pi-Apps Update" ]]
    [[ "$output" =~ "Task enabled" ]]
}

@test "Install: Show Email Config - Missing File" {
    # Ensure file is missing by overriding path to something non-existent
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; SSMTP_CONF=\"/tmp/nonexistent_ssmtp\"; show_email_config <<< ''"
    [[ "$output" =~ "No SSMTP configuration found" ]]
}

@test "Install: Download Scripts - All Success" {
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
touch "update_pi_os.sh" "update_pi_firmware.sh" "update_pip.sh" "docker_cleanup.sh" "update_pi_apps.sh"
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"
    mkdir -p "$HOME/pi-scripts"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; download_scripts"
    [[ "$output" =~ "Scripts updated" ]]
}

@test "Install: Main Menu - View Email Config (Missing)" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; SSMTP_CONF=\"/tmp/nonexistent_ssmtp\"; main_menu <<< $'2\\n\\n0'"
    [[ "$output" =~ "No SSMTP configuration found" ]]
}

@test "Install: Main Menu - Manage Tasks" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'3\\n0\\n0'"
    [[ "$output" =~ "Task Status Manager" ]]
}

@test "Install: Cron to Human - Invalid Day" {
    run bash -c "source ./install.sh; cron_to_human '0 0 * * 8'"
    [[ "$output" =~ "Dow 8" ]]
}

@test "Install: Manage Tasks UI - Toggle Task 1" {
    # Input: 1 (Toggle OS Update), y (Enable), \n (Default Time), 0 (Return)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; manage_tasks_ui <<< $'1\\ny\\n\\n0'"
    [[ "$output" =~ "Task: System OS Update" ]]
}

@test "Install: Main Menu - Uninstall Flow" {
    # Mock curl to return a simple script
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$*" == *"uninstall.sh"* ]]; then
    echo "echo MOCK_UNINSTALL"
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"
    
    # Ensure local uninstall.sh is missing to trigger curl path
    rm -f ./uninstall.sh
    
    # Input: 5 (Uninstall), y (Yes)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'5\\ny'"
    [[ "$output" =~ "MOCK_UNINSTALL" ]]
}

@test "Install: Entry Point - Manage Mode" {
    # Create install dir to trigger manage mode
    mkdir -p "$HOME/pi-scripts"
    
    # Use generic temp file to avoid modifying source
    cp ./install.sh ./install_temp_manage.sh
    
    # Mock main_menu to just exit
    sed -i 's/main_menu/exit 0 #/' ./install_temp_manage.sh
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; export HOME=$HOME; ./install_temp_manage.sh <<< '0'"
    
    rm -f ./install_temp_manage.sh
}

@test "Install: Entry Point - Fresh Mode" {
    # Ensure install dir is missing
    rm -rf "$HOME/pi-scripts"
    
    # Use generic temp file to avoid modifying source
    cp ./install.sh ./install_temp_fresh.sh
    
    # Mock run_fresh_install
    sed -i 's/run_fresh_install/exit 0 #/' ./install_temp_fresh.sh
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; export HOME=$HOME; ./install_temp_fresh.sh <<< '0'"
    
    rm -f ./install_temp_fresh.sh
}
