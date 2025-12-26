#!/usr/bin/env bats

setup() {
    export INSTALL_DIR="/tmp/scripts"
    export SSMTP_CONF="/tmp/ssmtp.conf"
    export REVALIASES="/tmp/revaliases"
    MOCK_DIR="$HOME/mocks"
    mkdir -p "$MOCK_DIR"
    
    # Global Mock Sudo
    cat << 'EOF' > "$MOCK_DIR/sudo"
#!/bin/bash
# Strip flags
while [[ "$1" == -* ]]; do shift; done
"$@"
EOF
    chmod +x "$MOCK_DIR/sudo"

    # Global Mock Crontab
    cat << 'EOF' > "$MOCK_DIR/crontab"
#!/bin/bash
# Check if -l flag is present (List/Read)
if [[ "$*" == *"-l"* ]]; then
    if [ -f "/tmp/mock_crontab" ]; then
        cat "/tmp/mock_crontab"
    else
        echo ""
    fi
else
    # Assume writing (e.g. crontab -)
    cat > /dev/null
fi
EOF
    chmod +x "$MOCK_DIR/crontab"

    # Mock tee, chown, chmod, usermod, sed
    echo "#!/bin/bash" > "$MOCK_DIR/tee"
    echo "cat > /dev/null" >> "$MOCK_DIR/tee"
    chmod +x "$MOCK_DIR/tee"

    for cmd in chown chmod usermod sed; do
        echo "#!/bin/bash" > "$MOCK_DIR/$cmd"
        chmod +x "$MOCK_DIR/$cmd"
    done
    
    # Ensure config files exist (simulating Docker image state)
    touch "$SSMTP_CONF"
    touch "$REVALIASES"
}

@test "Install: Configure Email - Invalid Email" {
    # File exists in Docker image, so it asks to reconfigure.
    # Input: Y (Yes repl) -> invalid_email -> enter (to return)
    # Ensure no lingering crontab
    rm -f /tmp/mock_crontab
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\ninvalid\n\n'"
    [[ "$output" =~ "Invalid email" ]]
}

@test "Install: Configure Email - Valid Config (New)" {
    rm -f /tmp/mock_crontab
    # Input: Y -> valid@test.com -> password
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\nvalid@test.com\nsecretpass'"
    [[ "$output" =~ "Email configured successfully" ]]
    [[ "$output" =~ "Saving configuration" ]]
}

@test "Install: Configure Email - Existing Config (No Update)" {
    rm -f /tmp/mock_crontab
    # Mock grep to return an existing user configuration
    # This avoids issues with real file writing/reading in the test environment
    cat << 'EOF' > "$MOCK_DIR/grep"
#!/bin/bash
# Allow grep to behave normally for other calls, but intercept configuration check
if [[ "$*" == *"AuthUser"* ]]; then
    echo "AuthUser=existing@test.com"
else
    # Fallback: install.sh uses grep often. Return 0 if match?
    # Actually, install.sh uses real grep. We should try to use real grep if possible?
    # No, we can just be specific.
    # If install.sh greps other things, we might break it.
    # Reverting to real grep would require fixing the file permission issue.
    # Let's hope install.sh only greps valid things in this path.
    # Logic: if not AuthUser, execute real grep? /bin/grep?
    if [ -x /bin/grep ]; then
        /bin/grep "$@"
    else
        # minimal fallback
        echo ""
    fi
fi
EOF
    chmod +x "$MOCK_DIR/grep"

    # Input: N (Do not reconfigure)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'N'"
    [[ "$output" =~ "Current Configured Email: existing@test.com" ]]
}

@test "Install: Toggle Task - Enable Disabled Task" {
    # Task 1 (OS Update) is DISABLED (default mock crontab is empty)
    rm -f /tmp/mock_crontab
    
    # Input: y (Enable) -> default time (Enter)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'y\n\n'"
    [[ "$output" =~ "Current Status: DISABLED" ]]
    [[ "$output" =~ "Task enabled" ]]
}

@test "Install: Toggle Task - Disable Enabled Task" {
    # Mock Task 1 being ENABLED via file
    echo "0 3 * * 0 $HOME/pi-scripts/update_pi_os.sh" > /tmp/mock_crontab
    
    # Input: y (Disable)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'y'"
    [[ "$output" =~ "Current Status: ENABLED" ]]
    [[ "$output" =~ "Task disabled" ]]
}

@test "Install: Toggle Task - Edit Enabled Task" {
    # Mock Task 1 being ENABLED via file
    echo "0 3 * * 0 $HOME/pi-scripts/update_pi_os.sh" > /tmp/mock_crontab
    
    # Input: e (Edit) -> new_time
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'e\n0 5 * * *'"
    [[ "$output" =~ "Current Status: ENABLED" ]]
    [[ "$output" =~ "Schedule updated" ]]
}


@test "Install: Download Scripts - Success and Failure" {
    # Mock Curl to succeed for script 1, fail for script 2
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$*" == *"update_pi_firmware.sh"* ]]; then
    exit 1 # Fail firmware download
else
    # Create dummy files for other scripts
    touch "update_pi_os.sh"
    touch "update_pip.sh"
    touch "update_pi_apps.sh"
    touch "docker_cleanup.sh"
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/curl"

    # Mock wget too just in case
    echo "#!/bin/bash" > "$MOCK_DIR/wget"
    chmod +x "$MOCK_DIR/wget"
    
    # Needs to see INSTALL_DIR
    mkdir -p "$HOME/pi-scripts"
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; download_scripts"
    
    # We expect some failures
    [[ "$output" =~ "Error downloading update_pi_firmware.sh" ]]
    [[ "$output" =~ "Scripts updated" ]]
}

@test "Install: Fresh Install Flow" {
    # Test the 'run_fresh_install' function logic
    # Mock apt-get
    echo "echo APT" > "$MOCK_DIR/apt-get"
    chmod +x "$MOCK_DIR/apt-get"
    
    # Inputs:
    # 1. Y (Reconfigure Email? - since it exists in Docker)
    # 2. test@fresh.com
    # 3. password
    # 4. Y (Enable OS Task) -> default schedule
    # 5. Y (Enable Firmware) -> default
    # 6. Y (Enable Docker) -> default
    # 7. Y (Enable Pi-Apps) -> default
    # 8. Y (Enable Pip) -> default
    # 9. Enter (Return from "Press Enter to open Manager")
    # 10. 0 (Exit from Manager)
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; run_fresh_install <<< $'Y\ntest@fresh.com\npassword\nY\n\nY\n\nY\n\nY\n\nY\n\n\n0'"
    
    [[ "$output" =~ "Welcome to the One-Line Installer" ]]
    [[ "$output" =~ "Installation Complete" ]]
}

@test "Install: Configure Email - Reconfigure Opt-out" {
    # File exists, user says No to reconfigure
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    # mv /tmp/ssmtp.conf /etc/ssmtp/ssmtp.conf -- Removed because writing directly to target
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'N'"
    [[ "$output" =~ "Current Configured Email: existing@test.com" ]]
}

@test "Install: Configure Email - Empty Password" {
    # User provides email but empty password
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\ntest@test.com\n'"
    [[ "$output" =~ "Password empty. Returning." ]]
}

@test "Install: Show Email Config - Missing File" {
    rm -f "$SSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; show_email_config <<< $''"
    [[ "$output" =~ "No SSMTP configuration found." ]]
}

@test "Install: Fresh Install - Opt out of Task" {
    # Test skipping a task during fresh install
    # 1. Y (Reconfig)
    # 2. Email/Pass
    # 3. n (Skip first task)
    # 4. Y x4 (Accept others)
    # 5. \n (Return), 0 (Exit)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; run_fresh_install <<< $'Y\ntest@fresh.com\npassword\nn\nY\n\nY\n\nY\n\nY\n\n\n0'"
    [[ "$output" =~ "Skipped System OS Update" ]]
}

@test "Install: Main Menu - Invalid Option" {
    # Input: 9 (invalid), then 0 (exit)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'9\n0'"
    [[ "$output" =~ "Invalid option." ]]
}

@test "Install: Main Menu - Uninstall No" {
    # Input: 5 (Uninstall), n (No), 0 (Exit)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'5\nn\n0'"
    [[ "$output" =~ "Manage Tasks" ]] # Should still be in menu
}

@test "Install: Main Menu - Uninstall Yes (Missing Local Script)" {
    # Mock curl to return uninstaller
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$*" == *"uninstall.sh"* ]]; then
    echo "echo MOCK_REMOTE_UNINSTALL"
else
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/curl"
    
    # Ensure local uninstall.sh is NOT found
    rm -f ./uninstall.sh
    
    # Input: 5 (Uninstall), y (Yes)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'5\ny'"
    [[ "$output" =~ "MOCK_REMOTE_UNINSTALL" ]]
}

@test "Install: Main Menu - EOF" {
    # No input, hits EOF
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< ''"
    [[ "$output" =~ "EOF detected" ]]
}
