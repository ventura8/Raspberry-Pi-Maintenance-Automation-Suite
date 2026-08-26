#!/usr/bin/env bats

# Interactive installer tests for install.sh

setup() {
    local repo_root
    repo_root="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

    export TEST_WORKSPACE
    TEST_WORKSPACE=$(mktemp -d)
    export MOCK_DIR="$TEST_WORKSPACE/mocks"
    export INSTALL_DIR="$TEST_WORKSPACE/scripts"
    export SSMTP_CONF="$TEST_WORKSPACE/ssmtp.conf"
    export MSMTP_CONF="$TEST_WORKSPACE/msmtprc"
    export REVALIASES="$TEST_WORKSPACE/revaliases"
    mkdir -p "$MOCK_DIR" "$INSTALL_DIR"
    : > "$SSMTP_CONF"
    : > "$MSMTP_CONF"
    : > "$REVALIASES"

    export TEST_MODE="true"
    unset INSTALL_USE_WHIPTAIL || true
    export INSTALL_FORCE_TEXT_UI="0"
    export INSTALL_UI_MODE=""

    (
        cd "$repo_root"
        # Honor workspace MOCK_DIR for isolated cron/mail mock state.
        MOCK_DIR="$MOCK_DIR" ./tests/setup_mocks.sh > /dev/null
    )
    export PATH="$MOCK_DIR:$PATH"

    cp "$repo_root/install.sh" "$TEST_WORKSPACE/"
    mkdir -p "$TEST_WORKSPACE/lib"
    cp "$repo_root/lib/"*.sh "$TEST_WORKSPACE/lib/"
    cp "$repo_root/VERSION" "$TEST_WORKSPACE/" 2> /dev/null || printf 'v0.0.0\n' > "$TEST_WORKSPACE/VERSION"
    SUITE_VERSION=$(tr -d '[:space:]' < "$TEST_WORKSPACE/VERSION")
    export SUITE_VERSION
    cd "$TEST_WORKSPACE"
}

teardown() {
    cd / > /dev/null || true
    rm -rf "${TEST_WORKSPACE:-}"
}

@test "Install: Configure Email - Invalid Email" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'Y\ninvalid-email\n\n'"
    [[ "$output" =~ "Invalid email" ]]
}

@test "Install: Configure Email - Valid Config (New)" {
    # No prior valid config exists (SSMTP_CONF/MSMTP_CONF are empty placeholders), so the
    # reconfigure-confirm prompt does not fire and the first line is the email directly.
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'test@test.com\npassword'"
    [[ "$output" =~ "Email configured successfully" ]]
    
    # Verify MAILTO was written to mock crontab
    run cat "$MOCK_DIR/root_cron"
    [[ "$output" =~ 'MAILTO="test@test.com"' ]]
}

@test "Install: Configure Email - Existing Config (No Update)" {
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'n'"
    # Should return early without asking for email
    [[ ! "$output" =~ "Enter Gmail address" ]]
}

@test "Install: Configure Email (text) - msmtp-only config shows current address" {
    rm -f "$SSMTP_CONF"
    printf 'account default\nhost smtp.gmail.com\nuser msmtp-only@test.com\n' > "$MSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:\$PATH INSTALL_FORCE_TEXT_UI=1; source ./install.sh; configure_email_text <<< $'n'"
    [[ "$output" =~ "Current Configured Email: msmtp-only@test.com" ]]
    [[ ! "$output" =~ "Enter Gmail address" ]]
}

@test "Install: Configure Email (whiptail) - msmtp-only config honors reconfigure prompt" {
    # The mocked whiptail doesn't echo dialog text, so assert behaviorally: answering "no" to
    # reconfigure must be honored (proving the msmtp-only config was recognized and the prompt
    # actually fired) rather than falling through and overwriting with the queued replacement.
    rm -f "$SSMTP_CONF"
    printf 'account default\nhost smtp.gmail.com\nuser msmtp-only@test.com\n' > "$MSMTP_CONF"
    printf '%s\n' "no" > "$MOCK_DIR/whiptail_yesno"
    printf 'new@test.com\nnewpass\n' > "$MOCK_DIR/whiptail_input"
    run bash -c \
        "export PATH=$MOCK_DIR:\$PATH INSTALL_USE_WHIPTAIL=1; source ./install.sh; \
configure_email_whiptail; grep -E '^user[[:space:]]+' \"$MSMTP_CONF\""
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "msmtp-only@test.com" ]]
    [[ ! "$output" =~ "new@test.com" ]]
}

@test "Install: Toggle Task - Enable Disabled Task" {
    # Ensure task 1 is disabled (remove from mock root cron)
    rm -f "$MOCK_DIR/root_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'y\n0 0 * * *'"
    [[ "$output" =~ "Task enabled" ]]
}

@test "Install: Toggle Task - Disable Enabled Task" {
    # Add task 1 to mock root cron
    echo "0 0 * * * $INSTALL_DIR/update_pi_os.sh >/dev/null" > "$MOCK_DIR/root_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'y'"
    [[ "$output" =~ "Task disabled" ]]
}

@test "Install: Toggle Task - Edit Enabled Task" {
    echo "0 0 * * * $INSTALL_DIR/update_pi_os.sh >/dev/null" > "$MOCK_DIR/root_cron"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; toggle_task 1 <<< $'e\n1 1 * * *'"
    [[ "$output" =~ "Schedule updated" ]]
}

@test "Install: Download Scripts - Success and Failure" {
    # Mock curl to fail for one specific call
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
outfile=""
args="$*"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then outfile="$2"; fi
  shift
done
if [[ "$args" == *"update_pi_firmware.sh"* ]]; then exit 1; fi
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
    [[ "$output" =~ "$SUITE_VERSION" ]]
    [[ "$output" =~ "Installation Complete" ]]
}

@test "Install: Configure Email - Reconfigure Opt-out" {
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'n'"
    [[ ! "$output" =~ "Enter Gmail address" ]]
}

@test "Install: Configure Email - Empty Password" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'test@test.com\n\n'"
    [[ "$output" =~ "Password empty" ]]
}

@test "Install: Show Email Config - Missing File" {
    rm -f "$SSMTP_CONF" "$MSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; show_email_config <<< $''"
    [[ "$output" =~ "No mail configuration found" ]]
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
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'6\nn\n0'"
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
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'6\ny'"
    
    cd - >/dev/null
    rm -rf "$TD"
    
    [[ "$output" =~ "MOCK_REMOTE_UNINSTALL" ]]
}

@test "Install: Main Menu - EOF" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu < /dev/null"
    [[ "$output" =~ "EOF detected" ]]
}

@test "Install: Check Dependencies - Installs Missing" {
    # Mock apt-get
    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
echo "Installing dependencies..."
EOF
    /usr/bin/chmod +x "$MOCK_DIR/apt-get"

    run bash -c "
        export PATH=$MOCK_DIR:\$PATH
        source ./install.sh
        
        # Override AFTER sourcing to force mail-transport install path
        has_mail_sender() { return 1; }
        is_installed() {
            if [[ \"\$1\" == \"whiptail\" ]]; then return 1; fi
            if [[ \"\$1\" == \"curl\" ]]; then return 0; fi
            command -v \"\$1\" &> /dev/null
        }
        
        check_dependencies
    "
    [[ "$output" =~ "Mail sender not found. Installing mail-transport" ]]
    [[ "$output" =~ "whiptail not found. Installing whiptail" ]]
}

@test "Install: Pi-Apps (User Crontab) Management" {
    # Add Pi-Apps to user crontab (ID 5)
    echo "0 5 * * 0 $INSTALL_DIR/update_pi_apps.sh >/dev/null" > "$MOCK_DIR/user_cron"

    # Mock crontab to read/write user file under this test's MOCK_DIR
    cat << EOF > "$MOCK_DIR/crontab"
#!/bin/bash
if [[ "\$*" == *"-l"* ]]; then
    if [ -f "$MOCK_DIR/user_cron" ]; then cat "$MOCK_DIR/user_cron"; else echo ""; fi
else
    cat > "$MOCK_DIR/user_cron"
fi
EOF
    chmod +x "$MOCK_DIR/crontab"

    # Toggle Pi-Apps (Disable)
    run bash -c "export PATH=$MOCK_DIR:\$PATH; source ./install.sh; toggle_task 5 <<< \$'y'"

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
0 0 * * * $INSTALL_DIR/update_pi_os.sh >/dev/null
0 0 1 * * $INSTALL_DIR/update_pi_firmware.sh >/dev/null
0 0 * * 1 $INSTALL_DIR/update_pip.sh >/dev/null
1 2 3 4 5 $INSTALL_DIR/docker_cleanup.sh >/dev/null
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

@test "Install: get_current_email_user and download_scripts use msmtp after migrate-then-reconfigure" {
    echo "AuthUser=old@test.com" > "$SSMTP_CONF"
    echo "AuthPass=oldpass" >> "$SSMTP_CONF"
    echo "mailhub=smtp.gmail.com:587" >> "$SSMTP_CONF"
    rm -f "$MSMTP_CONF"
    mkdir -p "$INSTALL_DIR"

    # Stale SSMTP_CONF (old@test.com) is intentionally left in place after migration+reconfigure
    # to prove MSMTP_CONF (new@test.com) takes precedence, matching send_mail's own preference.
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
outfile=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "-o" ]; then outfile="$arg"; fi
    prev="$arg"
done
if [[ "$*" =~ "scripts/test_script.sh" ]]; then
    [ -n "$outfile" ] && printf '%s\n' 'RECIPIENT_EMAIL="placeholder@example.com"' > "$outfile"
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"

    run bash -c "
        export PATH=$MOCK_DIR:\$PATH INSTALL_DIR=$INSTALL_DIR
        source ./install.sh
        migrate_mail_config_to_msmtp
        write_mail_config 'new@test.com' 'newpass'
        get_current_email_user
        SCRIPTS[1]='test_script.sh'
        download_scripts > /dev/null
        cat \"$INSTALL_DIR/test_script.sh\"
    "
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "new@test.com" ]]
    [[ "$output" != *"old@test.com"* ]]
}

@test "Install: get_current_email_user resolves default account via inheritance" {
    rm -f "$SSMTP_CONF"
    cat << 'EOF' > "$MSMTP_CONF"
defaults
auth on
tls on

account personal
host smtp.gmail.com
user inherited@test.com
password secret

account default : personal
EOF
    run bash -c "export PATH=$MOCK_DIR:\$PATH; source ./install.sh; get_current_email_user"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "inherited@test.com" ]]
}

@test "Install: Uninstall - Local Script" {
    # Create a mock uninstall script
    echo "#!/bin/bash" > "./uninstall.sh"
    echo "echo 'LOCAL_UNINSTALL_RUN'" >> "./uninstall.sh"
    chmod +x "./uninstall.sh"
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'6\ny'"
    
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

@test "Install: Run Enabled Tasks Now - Runs Root and User Tasks" {
    mkdir -p "$INSTALL_DIR"

    cat << 'EOF' > "$INSTALL_DIR/update_pi_os.sh"
#!/bin/bash
echo "RUN_OS_UPDATE"
EOF
    chmod +x "$INSTALL_DIR/update_pi_os.sh"

    cat << 'EOF' > "$INSTALL_DIR/update_pi_apps.sh"
#!/bin/bash
echo "RUN_PI_APPS_UPDATE"
EOF
    chmod +x "$INSTALL_DIR/update_pi_apps.sh"

    echo "0 3 * * 0 $INSTALL_DIR/update_pi_os.sh >/dev/null" > "$MOCK_DIR/root_cron"
    echo "0 5 * * 0 $INSTALL_DIR/update_pi_apps.sh >/dev/null" > "$MOCK_DIR/user_cron"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; run_enabled_tasks_now <<< $'y\\n\\n'"

    [[ "$output" =~ "RUN_OS_UPDATE" ]]
    [[ "$output" =~ "RUN_PI_APPS_UPDATE" ]]
    [[ "$output" =~ "All enabled tasks completed successfully" ]]
}

@test "Install: Run Enabled Tasks Now - Cancel on Reboot Warning" {
    mkdir -p "$INSTALL_DIR"

    cat << 'EOF' > "$INSTALL_DIR/update_pi_os.sh"
#!/bin/bash
echo "RUN_OS_UPDATE_SHOULD_NOT_HAPPEN"
EOF
    chmod +x "$INSTALL_DIR/update_pi_os.sh"

    echo "0 3 * * 0 $INSTALL_DIR/update_pi_os.sh >/dev/null" > "$MOCK_DIR/root_cron"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; run_enabled_tasks_now <<< $'n\\n\\n'"

    [[ "$output" =~ "Warning: One or more enabled tasks may reboot" ]]
    [[ "$output" =~ "Cancelled: Enabled tasks were not run" ]]
    [[ ! "$output" =~ "RUN_OS_UPDATE_SHOULD_NOT_HAPPEN" ]]
}

@test "Install: Run Enabled Tasks Now - No Enabled Tasks" {
    rm -f "$MOCK_DIR/root_cron" "$MOCK_DIR/user_cron"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; run_enabled_tasks_now <<< $'\\n'"

    [[ "$output" =~ "No enabled tasks found" ]]
}

@test "Install: Run Enabled Tasks Now - Missing Script Reports Failure" {
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # Enable a reboot-capable root task, but intentionally do not create the script file.
    echo "0 3 * * 0 $INSTALL_DIR/update_pi_os.sh >/dev/null" > "$MOCK_DIR/root_cron"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; run_enabled_tasks_now <<< $'y\\n\\n'"

    [[ "$output" =~ "Skipped: Script not found" ]]
    [[ "$output" =~ "Completed with failures" ]]
}

@test "Install: Main Menu - Run Enabled Tasks Option" {
    mkdir -p "$INSTALL_DIR"

    cat << 'EOF' > "$INSTALL_DIR/update_pi_os.sh"
#!/bin/bash
echo "RUN_OS_UPDATE_MENU"
EOF
    chmod +x "$INSTALL_DIR/update_pi_os.sh"

    echo "0 3 * * 0 $INSTALL_DIR/update_pi_os.sh >/dev/null" > "$MOCK_DIR/root_cron"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'5\\ny\\n\\n0'"

    [[ "$output" =~ "Run Enabled Tasks Now" ]]
    [[ "$output" =~ "RUN_OS_UPDATE_MENU" ]]
}

@test "Install: Main Menu - Force Update Scripts Option" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; main_menu <<< $'4\n0'"

    [[ "$output" =~ "Downloading/Updating scripts" ]]
    [[ "$output" =~ "Scripts updated" ]]
}

@test "Install: Entry Point - Fresh Install" {
    rm -rf "$INSTALL_DIR"
    # Execute directly.
    # Pass inputs for fresh install (Y, email, pass, accept tasks..., enter, 0 exit menu)
    run ./install.sh <<< $'Y\ntest@entry.com\npassword\n\n\n\n\n\n\n\n\n0'
    
    [[ "$output" =~ "Raspberry Pi Maintenance Suite $SUITE_VERSION" ]]
    [[ "$output" =~ "Welcome to the One-Line Installer" ]]
    [[ "$output" =~ "Installation Complete" ]]
}
@test "Install: Configure Email - Strips Spaces and Carriage Returns" {
    # Define an email and password with spaces and CRs
    # In bash $'...' strings, \r correctly inserts a carriage return
    # We want to verify that " test@test.com  " and " pass word " become "test@test.com" and "password"
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $' test@test.com \r\n pass word \r'"
    
    # Verify via show_email_config or checking the file directly
    [[ "$output" =~ "Email configured successfully" ]]

    # Check the actual config file (msmtp is preferred over ssmtp)
    run grep "^user" "$MSMTP_CONF"
    [[ "$output" == "user           test@test.com" ]]

    run grep "^password" "$MSMTP_CONF"
    [[ "$output" == "password       password" ]]
}
@test "Install: Configure Email - Strips Internal Spaces from App Password" {
    # Test internal spaces removal (Google format: 'aaaa bbbb cccc dddd')
    run bash -c "export PATH=$MOCK_DIR:$PATH; source ./install.sh; configure_email_interactive <<< $'test@test.com\naaaa bbbb cccc dddd'"
    
    [[ "$output" =~ "Email configured successfully" ]]
    
    # Check that password has no spaces
    run grep "^password" "$MSMTP_CONF"
    [[ "$output" == "password       aaaabbbbccccdddd" ]]
}

@test "Install: MATRIX_FRESH non-interactive install" {
    rm -rf "$INSTALL_DIR"
    run env PATH="$MOCK_DIR:$PATH" INSTALL_MATRIX_FRESH=1 \
        MATRIX_EMAIL="matrix@test.com" MATRIX_PASS="secretpass" \
        INSTALL_DIR="$INSTALL_DIR" SSMTP_CONF="$SSMTP_CONF" REVALIASES="$REVALIASES" \
        TEST_MODE=true INSTALL_FORCE_TEXT_UI=1 \
        ./install.sh

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Matrix/non-interactive fresh install" ]]
    [[ "$output" =~ "Installation Complete" ]]
    [[ "$output" =~ "Enabled" ]]
    [ -f "$INSTALL_DIR/.version" ]
    [ -f "$INSTALL_DIR/update_pi_os.sh" ]
    [ -f "$INSTALL_DIR/lib/os_pkg.sh" ]
}

@test "Install: lib download HTTP failure is reported" {
    rm -rf "$TEST_WORKSPACE/lib"
    mkdir -p "$INSTALL_DIR"
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$*" == *"/lib/"* ]]; then
    exit 22
fi
outfile=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then outfile="$a"; fi
  prev="$a"
done
[ -n "$outfile" ] && : > "$outfile"
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"
    run bash -c "export PATH=$MOCK_DIR:\$PATH; source ./install.sh; download_scripts"
    [[ "$output" =~ "Error downloading lib/" ]]
}
