#!/usr/bin/env bats

setup() {
    # Use shared mock setup first to define MOCK_DIR
    source ./tests/setup_mocks.sh

    # Define installation directory
    export INSTALL_DIR="$HOME/pi-scripts"
    
    # Point system files to writable mock locations
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    export REVALIASES="$MOCK_DIR/revaliases"
    export REBOOT_REQUIRED_FILE="$MOCK_DIR/reboot-required"

    # Point system files to writable mock locations
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    export REVALIASES="$MOCK_DIR/revaliases"
    export REBOOT_REQUIRED_FILE="$MOCK_DIR/reboot-required"

    # Create safety copy of install.sh with execution logic stripped
    # Use grep to find the line number of the Entry Point to avoid regex issues
    CUT_LINE=$(grep -n "# --- Entry Point ---" ./install.sh | head -n 1 | cut -d: -f1)
    if [ -n "$CUT_LINE" ]; then
        head -n "$((CUT_LINE - 1))" ./install.sh > "$MOCK_DIR/install_lib.sh"
    else
        # Fallback if pattern not found (should not happen)
        cp ./install.sh "$MOCK_DIR/install_lib.sh"
    fi
    
    # Check for and fix tainted content (where main_menu was replaced by exit 0 #)
    # This happens due to other tests modifying the file in the shared environment
    if grep -q "exit 0 #" "$MOCK_DIR/install_lib.sh"; then
       sed -i 's/exit 0 #/main_menu/g' "$MOCK_DIR/install_lib.sh"
    fi
}

# --- Install Script Component Tests ---
# Check Dependencies test skipped due to complexity mocking builtin 'command'

@test "Component: Install - Download Scripts (Success)" {
    # Mock Curl (Success)
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$3" =~ "scripts/test_script.sh" ]]; then
    touch "$INSTALL_DIR/test_script.sh"
fi
EOF
    chmod +x "$MOCK_DIR/curl"

    # Mock Sudo specific for grep in download_scripts
    # Ideally should use global mock, but download_scripts uses `sudo grep`
    # The global mock handles args and runs command.
    # The real command 'grep' will be the mock grep if we setup PATH correctly.
    # setup_mocks.sh adds mocks to PATH.
    
    # Needs a mock text file for grep to read
    mkdir -p "$(dirname "$SSMTP_CONF")"
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"

    # Ensure INSTALL_DIR exists and is writable
    mkdir -p "$INSTALL_DIR"

    # Ensure INSTALL_DIR exists and is writable
    mkdir -p "$INSTALL_DIR"

    # Ensure INSTALL_DIR exists and is writable
    mkdir -p "$INSTALL_DIR"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source \"$MOCK_DIR/install_lib.sh\"; SCRIPTS[1]='test_script.sh'; download_scripts"
    
    # Cleanup
    rm -f "test_script.sh"
    
    [[ "$output" =~ "Scripts updated" ]]
}

@test "Component: Install - Get Task Status (Reads Crontab)" {
    # Mock crontab
    cat << 'EOF' > "$MOCK_DIR/crontab"
#!/bin/bash
if [[ "$*" == *"-l"* ]]; then
    echo "0 0 * * * $INSTALL_DIR/test_script.sh"
else
    # Install
    cat
fi
EOF
    chmod +x "$MOCK_DIR/crontab"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source \"$MOCK_DIR/install_lib.sh\"; get_task_status 'test_script.sh' 'false'"
    
    [[ "$output" =~ "ENABLED|0 0 * * *" ]]
}

# --- Update Scripts Component Tests ---

@test "Component: OS Update - Uses full-upgrade" {

    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
if [[ "$*" == *"full-upgrade"* ]]; then echo "SUCCESS_FULL_UPGRADE"; fi
EOF
    chmod +x "$MOCK_DIR/apt-get"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_os.sh"
    [[ "$output" =~ "SUCCESS_FULL_UPGRADE" ]]
}

@test "Component: OS Update - Detects Reboot Required (Negative)" {

    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
echo "Doing nothing"
EOF
    chmod +x "$MOCK_DIR/apt-get"
    chmod +x "$MOCK_DIR/apt-get"
    rm -f "$REBOOT_REQUIRED_FILE"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_os.sh"
    [[ "$output" =~ "No reboot is required" ]]
}

@test "Component: OS Update - Detects Reboot Required (Positive)" {

    # Ensure shutdown is mocked to prevent errors
    cat << 'EOF' > "$MOCK_DIR/shutdown"
#!/bin/bash
echo "SHUTDOWN_CALLED"
EOF
    chmod +x "$MOCK_DIR/shutdown"
    
    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
echo "Doing nothing"
EOF
    chmod +x "$MOCK_DIR/apt-get"
    # Create the reboot flag file
    touch "$REBOOT_REQUIRED_FILE"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_os.sh"
    
    # Cleanup
    rm -f "$REBOOT_REQUIRED_FILE"
    
    [[ "$output" =~ "A reboot is required" ]]
    [[ "$output" =~ "SHUTDOWN_CALLED" ]]
}

@test "Component: Docker Cleanup - Auto-detects Buildx" {

    cat << 'EOF' > "$MOCK_DIR/docker"
#!/bin/bash
if [[ "$1" == "buildx" && "$2" == "version" ]]; then exit 0;
elif [[ "$1" == "buildx" && "$2" == "prune" ]]; then echo "BUILDX_PRUNE_CALLED";
fi
EOF
    chmod +x "$MOCK_DIR/docker"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/docker_cleanup.sh"
    [[ "$output" =~ "BUILDX_PRUNE_CALLED" ]]
}

@test "Component: Docker Cleanup - Legacy Builder" {

    cat << 'EOF' > "$MOCK_DIR/docker"
#!/bin/bash
if [[ "$1" == "buildx" && "$2" == "version" ]]; then exit 1; # Fail buildx check
elif [[ "$1" == "builder" && "$2" == "prune" ]]; then echo "LEGACY_BUILDER_CALLED";
fi
EOF
    chmod +x "$MOCK_DIR/docker"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/docker_cleanup.sh"
    [[ "$output" =~ "LEGACY_BUILDER_CALLED" ]]
}

@test "Component: Pip Update - Runs Correctly" {

    cat << 'EOF' > "$MOCK_DIR/pip3"
#!/bin/bash
if [[ "$*" == *"list"* ]]; then
    echo "Package Version Latest Type"
    echo "------- ------- ------ ----"
    echo "fake-pkg 1.0.0 2.0.0 wheel"
elif [[ "$*" == *"install"* ]]; then
    echo "PIP_INSTALL_CALLED"
fi
EOF
    chmod +x "$MOCK_DIR/pip3"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pip.sh"
    [[ "$output" =~ "PIP_INSTALL_CALLED" ]]
}

@test "Component: Pi-Apps - Updates and Sends Email" {

    # Create the mock in the standard location expected by the script
    mkdir -p "$HOME/pi-apps"
    cat << 'EOF' > "$HOME/pi-apps/updater"
#!/bin/bash
echo "cli-yes"
EOF
    chmod +x "$HOME/pi-apps/updater"
    
    # Create the mock in the standard location expected by the script
    # Note: docker environment uses /home/pi, so we should ensure we write there or override HOME
    mkdir -p "$HOME/pi-apps"
    cat << 'EOF' > "$HOME/pi-apps/updater"
#!/bin/bash
echo "cli-yes"
EOF
    chmod +x "$HOME/pi-apps/updater"
    
    # Mock SSMTP again specifically for this test to ensure it catches output
    cat << 'EOF' > "$MOCK_DIR/ssmtp"
#!/bin/bash
echo "EMAIL_SENT_HEADER"
cat
EOF
    chmod +x "$MOCK_DIR/ssmtp"

    # Bypass mock chmod to ensure the script is actually executable
    /usr/bin/chmod +x "$HOME/pi-apps/updater"

    # Run without overriding HOME since we wrote to real HOME (in docker this is /home/pi)
    run bash -c "ls -la $HOME/pi-apps/updater; export PATH=$MOCK_DIR:\$PATH; ./scripts/update_pi_apps.sh"
    
    if [[ ! "$output" =~ "cli-yes" ]]; then
        echo "Output: $output" >&3
    fi

    # We expect "cli-yes" in the output
    [[ "$output" =~ "cli-yes" ]]
    [[ "$output" =~ "EMAIL_SENT_HEADER" ]]
}

@test "Component: Pi-Apps - Updater Missing" {

    # Ensure updater is MISSING
    SETUP_CMD='export HOME="$MOCK_DIR"; mkdir -p "$HOME/pi-apps"; rm -f "$HOME/pi-apps/updater"; '
    
    run bash -c "${SETUP_CMD} export PATH=$MOCK_DIR:$PATH; export HOME=$MOCK_DIR; ./scripts/update_pi_apps.sh"
    [[ "$output" =~ "Pi-Apps updater not found" ]]
}

@test "Component: Firmware - Update Available & Reboot" {

    cat << 'EOF' > "$MOCK_DIR/rpi-eeprom-update"
#!/bin/bash
echo "UPDATE SUCCESSFUL"
echo "Secure boot: active"
EOF
    chmod +x "$MOCK_DIR/rpi-eeprom-update"
    
    cat << 'EOF' > "$MOCK_DIR/shutdown"
#!/bin/bash
echo "SHUTDOWN_SCHEDULED"
EOF
    chmod +x "$MOCK_DIR/shutdown"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_firmware.sh"
    [[ "$output" =~ "UPDATE SUCCESSFUL" ]]
    [[ "$output" =~ "SHUTDOWN_SCHEDULED" ]]
}

@test "Component: Firmware - No Update Needed" {

    cat << 'EOF' > "$MOCK_DIR/rpi-eeprom-update"
#!/bin/bash
echo "BOOTLOADER: up-to-date"
EOF
    chmod +x "$MOCK_DIR/rpi-eeprom-update"
    
    cat << 'EOF' > "$MOCK_DIR/shutdown"
#!/bin/bash
echo "FAIL_SHOULD_NOT_REBOOT"
EOF
    chmod +x "$MOCK_DIR/shutdown"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_firmware.sh"
    
    [[ "$output" =~ "No firmware update was applied" ]]
    [[ ! "$output" =~ "FAIL_SHOULD_NOT_REBOOT" ]]
}
@test "Component: Firmware - fwupd Update Available & Reboot" {
    # Ensure rpi-eeprom-update is MISSING
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    
    # Mock fwupdmgr
    cat << 'EOF' > "$MOCK_DIR/fwupdmgr"
#!/bin/bash
if [[ "$1" == "refresh" ]]; then
    exit 0
elif [[ "$1" == "get-updates" ]]; then
    exit 0 # Updates available
elif [[ "$1" == "update" ]]; then
    echo "Successfully installed"
    echo "Restarting device..."
fi
EOF
    /bin/chmod +x "$MOCK_DIR/fwupdmgr"
    
    cat << 'EOF' > "$MOCK_DIR/shutdown"
#!/bin/bash
echo "SHUTDOWN_SCHEDULED"
EOF
    /bin/chmod +x "$MOCK_DIR/shutdown"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_firmware.sh"
    [[ "$output" =~ "fwupdmgr" ]]
    [[ "$output" =~ "Successfully installed" ]]
    [[ "$output" =~ "SHUTDOWN_SCHEDULED" ]]
}

@test "Component: Firmware - fwupd No Update" {

    # Ensure rpi-eeprom-update is MISSING
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    
    # Mock fwupdmgr
    cat << 'EOF' > "$MOCK_DIR/fwupdmgr"
#!/bin/bash
if [[ "$1" == "get-updates" ]]; then
    exit 1 # No updates available
fi
EOF
    /bin/chmod +x "$MOCK_DIR/fwupdmgr"
    
    cat << 'EOF' > "$MOCK_DIR/shutdown"
#!/bin/bash
echo "FAIL_SHOULD_NOT_REBOOT"
EOF
    chmod +x "$MOCK_DIR/shutdown"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_firmware.sh"
    
    [[ "$output" =~ "No updates available" ]]
    [[ ! "$output" =~ "FAIL_SHOULD_NOT_REBOOT" ]]
}

@test "Component: Firmware - Automatic Dependency Installation" {
    # Ensure neither rpi-eeprom-update nor fwupdmgr are in PATH/MOCK_DIR
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    rm -f "$MOCK_DIR/fwupdmgr"
    
    # Mock apt-get to show installation attempt
    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
if [[ "$*" == *"install"* ]]; then
    echo "INSTALL_CALLED_FOR: $@"
    # After install, we "create" the mock tool to allow script to continue
    echo "#!/bin/bash" > "/tmp/mocks/fwupdmgr"
    echo "echo 'MOCKED FWUPDMGR'" >> "/tmp/mocks/fwupdmgr"
    chmod +x "/tmp/mocks/fwupdmgr"
fi
EOF
    chmod +x "$MOCK_DIR/apt-get"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_firmware.sh"
    
    [[ "$output" =~ "Dependencies installed successfully" ]]
    [[ "$output" =~ "Running 'fwupdmgr'" ]]
}

@test "Component: Firmware - Automatic Dependency Failure" {
    # Ensure neither rpi-eeprom-update nor fwupdmgr are in PATH/MOCK_DIR
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    rm -f "$MOCK_DIR/fwupdmgr"
    
    # Mock apt-get failure
    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
if [[ "$*" == *"install"* ]]; then
    exit 1
fi
EOF
    chmod +x "$MOCK_DIR/apt-get"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_firmware.sh"
    
    [[ "$output" =~ "Warning: Some dependencies may have failed to install" ]]
}
@test "Component: Install - Version Tracking" {
    # Mock Curl for both script download AND API call
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$*" =~ "api.github.com" ]]; then
    echo "{\"sha\": \"test_sha_123\"}"
elif [[ "$*" =~ "scripts/test_script.sh" ]]; then
    touch "$INSTALL_DIR/test_script.sh"
fi
EOF
    chmod +x "$MOCK_DIR/curl"

    # Mock grep/cut support files
    mkdir -p "$(dirname "$SSMTP_CONF")"
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    mkdir -p "$INSTALL_DIR"

    # Run download_scripts
    run bash -c "export PATH=$MOCK_DIR:$PATH; source \"$MOCK_DIR/install_lib.sh\"; SCRIPTS[1]='test_script.sh'; download_scripts"
    
    # Verify .version file created
    [[ -f "$INSTALL_DIR/.version" ]]
    [[ "$(cat "$INSTALL_DIR/.version")" == "test_sha_123" ]]
    [[ "$output" =~ "Version set to: test_sha_123" ]]
}
