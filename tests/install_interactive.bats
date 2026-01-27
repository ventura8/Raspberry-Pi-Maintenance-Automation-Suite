#!/usr/bin/env bats

# Interactive installer tests for install.sh

setup() {
    export MOCK_DIR="/tmp/mocks"
    export INSTALL_DIR="/tmp/scripts"
    rm -rf "$INSTALL_DIR"
    export SSMTP_CONF="/tmp/ssmtp.conf"
    export REVALIASES="/tmp/revaliases"
    export TEST_MODE="true"
    
    # Always ensure clean shared mocks
    # Use absolute path or relative to BATS_TEST_DIRNAME if easier, but we are in root initially
    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"
    
    # Reset Config Files

    # Reset Config Files
    > "$SSMTP_CONF"
    > "$REVALIASES"

    # Isolate Execution
    export TEST_WORKSPACE=$(mktemp -d)
    cp ./install.sh "$TEST_WORKSPACE/"
    cd "$TEST_WORKSPACE"
}

@test "Install: Configure Email - Invalid Email" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\ninvalid-email\n\n'"
    [[ "$output" =~ "Invalid email" ]]
}

@test "Install: Configure Email - Valid Config (New)" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\ntest@test.com\npassword'"
    [[ "$output" =~ "Email configured successfully" ]]
}

@test "Install: Configure Email - Existing Config (No Update)" {
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'n'"
    # Should return early without asking for email
    [[ ! "$output" =~ "Enter Gmail address" ]]
}

@test "Install: Toggle Task - Enable Disabled Task" {
    # Ensure task 1 is disabled (remove from mock root cron)
    rm -f "$MOCK_DIR/root_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'y\n0 0 * * *'"
    [[ "$output" =~ "Task enabled" ]]
}

@test "Install: Toggle Task - Disable Enabled Task" {
    # Add task 1 to mock root cron
    echo "0 0 * * * $INSTALL_DIR/update_pi_os.sh" > "$MOCK_DIR/root_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'y'"
    [[ "$output" =~ "Task disabled" ]]
}

@test "Install: Toggle Task - Edit Enabled Task" {
    echo "0 0 * * * $INSTALL_DIR/update_pi_os.sh" > "$MOCK_DIR/root_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'e\n1 1 * * *'"
    [[ "$output" =~ "Schedule updated" ]]
}

@test "Install: Download Scripts - Success and Failure" {
    # Mock curl to fail for one specific call
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
outfile=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then outfile="$2"; fi
  shift
done
if [[ "$outfile" == *"update_pi_firmware.sh"* ]]; then exit 1; fi
touch "$outfile"
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"
    
    mkdir -p "$INSTALL_DIR"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; download_scripts"
    [[ "$output" =~ "Error downloading update_pi_firmware.sh" ]]
    [[ "$output" =~ "Scripts updated" ]]
}

@test "Install: Fresh Install Flow" {
    # 1. Y (Reconfigure Email)
    # 2. test@fresh.com (Email)
    # 3. password (Password)
    # 4-9. \n x6 (Accept all 6 tasks)
    # 10. \n (Press Enter to open Manager)
    # 11. 0 (Exit)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; run_fresh_install <<< $'Y\ntest@fresh.com\npassword\n\n\n\n\n\n\n\n0'"
    
    [[ "$output" =~ "Welcome to the One-Line Installer" ]]
    [[ "$output" =~ "Installation Complete" ]]
}

@test "Install: Configure Email - Reconfigure Opt-out" {
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'n'"
    [[ ! "$output" =~ "Enter Gmail address" ]]
}

@test "Install: Configure Email - Empty Password" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\ntest@test.com\n\n'"
    [[ "$output" =~ "Password empty" ]]
}

@test "Install: Show Email Config - Missing File" {
    rm -f "$SSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; show_email_config <<< $''"
    [[ "$output" =~ "No SSMTP configuration found" ]]
}

@test "Install: Fresh Install - Opt out of Task" {
    # 1. Y (Reconfig Email)
    # 2. test@fresh.com
    # 3. password
    # 4. n (Skip OS Update)
    # 5-9. \n x5 (Accept others)
    # 10. \n (Press Enter)
    # 11. 0 (Exit)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; run_fresh_install <<< $'Y\ntest@fresh.com\npassword\nn\n\n\n\n\n\n\n0'"
    [[ "$output" =~ "Skipped System OS Update" ]]
}

@test "Install: Main Menu - Invalid Option" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'9\n0'"
    [[ "$output" =~ "Invalid option" ]]
}

@test "Install: Main Menu - Uninstall No" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'5\nn\n0'"
    [[ "$output" =~ "Configure Email Settings" ]] # Should still be in menu
}

@test "Install: Main Menu - Uninstall Yes (Missing Local Script)" {
    # Use clean mocks but override curl for this test
    # Mock curl to return uninstaller
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
echo 'echo "MOCK_REMOTE_UNINSTALL"'
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"
    
    # Ensure local uninstall.sh is missing to trigger curl path
    TD=$(mktemp -d)
    cp ./install.sh "$TD/"
    cd "$TD"
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'5\ny'"
    
    cd - >/dev/null
    rm -rf "$TD"
    
    [[ "$output" =~ "MOCK_REMOTE_UNINSTALL" ]]
}

@test "Install: Main Menu - EOF" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu < /dev/null"
    [[ "$output" =~ "EOF detected" ]]
}

@test "Install: Check Dependencies - Installs Missing" {
    # Mock command to fail for ssmtp
    cat << 'EOF' > "$MOCK_DIR/command"
#!/bin/bash
if [[ "$*" == *"-v ssmtp"* ]]; then exit 1; fi
builtin command "$@"
EOF
    chmod +x "$MOCK_DIR/command"
    
    # Mock apt-get
    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
echo "Installing dependencies..."
EOF
    chmod +x "$MOCK_DIR/apt-get"

    # We need to export a function to override 'command' builtin if possible, 
    # but 'command' is a keyword/builtin. Hard to mock in bash script sourcing.
    # However, check_dependencies uses `command -v`.
    # Tests run in bash -c.
    # Alternatives: define function `command` in the sourced script environment.
    
    run bash -c "
        export PATH=$MOCK_DIR:\$PATH
        source ./install.sh
        
        # Override AFTER sourcing to prevent overwrite
        is_installed() {
            if [[ \"\$1\" == \"ssmtp\" ]]; then return 1; fi
            command -v \"\$1\" &> /dev/null
        }
        
        check_dependencies
    "
    [[ "$output" =~ "ssmtp not found. Installing ssmtp" ]]
}

@test "Install: Pi-Apps (User Crontab) Management" {
    # Add Pi-Apps to user crontab (ID 5)
    echo "0 5 * * 0 $INSTALL_DIR/update_pi_apps.sh" > "$MOCK_DIR/user_cron"
    
    # Mock crontab to read/write user file
    cat << 'EOF' > "$MOCK_DIR/crontab"
#!/bin/bash
if [[ "$*" == *"-l"* ]]; then
    if [ -f "/tmp/mocks/user_cron" ]; then cat "/tmp/mocks/user_cron"; else echo ""; fi
else
    cat > "/tmp/mocks/user_cron"
fi
EOF
    chmod +x "$MOCK_DIR/crontab"

    # Toggle Pi-Apps (Disable)
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 5 <<< $'y'"
    
    [[ "$output" =~ "Task disabled" ]]
    # Verify file is empty/line removed
    run bash -c "cat $MOCK_DIR/user_cron"
    [[ ! "$output" =~ "update_pi_apps.sh" ]]
}

@test "Install: Verify Cron Human Readable Logic (Coverage)" {
    # Setup root cron with diverse schedules to hit all branches of cron_to_human
    # 1. Daily
    # 2. Monthly
    # 3. Weekly (Mon)
    # 4. Custom
    cat << EOF > "$MOCK_DIR/root_cron"
0 0 * * * $INSTALL_DIR/update_pi_os.sh
0 0 1 * * $INSTALL_DIR/update_pi_firmware.sh
0 0 * * 1 $INSTALL_DIR/update_pip.sh
1 2 3 4 5 $INSTALL_DIR/docker_cleanup.sh
EOF

    # Just viewing the menu exercises cron_to_human via manage_tasks_ui
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; manage_tasks_ui <<< $'0'"
    
    [[ "$output" =~ "Daily" ]]
    [[ "$output" =~ "Monthly" ]]
    [[ "$output" =~ "Weekly Mon" ]]
    [[ "$output" =~ "Custom Schedule" ]]
}

@test "Install: Show Email Config - Existing File" {
    echo "AuthUser=test@test.com" > "$SSMTP_CONF"
    echo "mailhub=smtp.test.com" >> "$SSMTP_CONF"
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; show_email_config <<< $''"
    
    [[ "$output" =~ "User:     test@test.com" ]]
}

@test "Install: Uninstall - Local Script" {
    # Create a mock uninstall script
    echo "#!/bin/bash" > "./uninstall.sh"
    echo "echo 'LOCAL_UNINSTALL_RUN'" >> "./uninstall.sh"
    chmod +x "./uninstall.sh"
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'5\ny'"
    
    # Cleanup
    rm -f "./uninstall.sh"
    
    [[ "$output" =~ "LOCAL_UNINSTALL_RUN" ]]
}

@test "Install: Entry Point - Detected Installed (Main Menu)" {
    mkdir -p "$INSTALL_DIR"
    # Execute directly, do NOT source.
    # Pass 0 to exit menu.
    run ./install.sh <<< $'0'
    [[ "$output" =~ "Raspberry Pi Maintenance Suite Manager" ]]
}

@test "Install: Entry Point - Fresh Install" {
    rm -rf "$INSTALL_DIR"
    # Execute directly.
    # Pass inputs for fresh install (Y, email, pass, accept tasks..., enter, 0 exit menu)
    run ./install.sh <<< $'Y\ntest@entry.com\npassword\n\n\n\n\n\n\n\n\n0'
    
    [[ "$output" =~ "Welcome to the One-Line Installer" ]]
    [[ "$output" =~ "Installation Complete" ]]
}
@test "Install: Configure Email - Strips Spaces and Carriage Returns" {
    # Define an email and password with spaces and CRs
    # In bash $'...' strings, \r correctly inserts a carriage return
    # We want to verify that " test@test.com  " and " pass word " become "test@test.com" and "password"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\n test@test.com \r\n pass word \r'"
    
    # Verify via show_email_config or checking the file directly
    [[ "$output" =~ "Email configured successfully" ]]
    
    # Check the actual config file
    run grep "^AuthUser=" "$SSMTP_CONF"
    [[ "$output" == "AuthUser=test@test.com" ]]
    
    run grep "^AuthPass=" "$SSMTP_CONF"
    [[ "$output" == "AuthPass=password" ]]
}
@test "Install: Configure Email - Strips Internal Spaces from App Password" {
    # Test internal spaces removal (Google format: 'aaaa bbbb cccc dddd')
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\ntest@test.com\naaaa bbbb cccc dddd'"
    
    [[ "$output" =~ "Email configured successfully" ]]
    
    # Check that AuthPass has no spaces
    run grep "^AuthPass=" "$SSMTP_CONF"
    [[ "$output" == "AuthPass=aaaabbbbccccdddd" ]]
}
