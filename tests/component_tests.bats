#!/usr/bin/env bats

setup() {
    # Use shared mock setup first to define MOCK_DIR
    source ./tests/setup_mocks.sh

    # Isolate from host/repo bind-mounts and parallel distro containers.
    export INSTALL_DIR="${INSTALL_DIR:-/tmp/pi-scripts-component-$$}"
    mkdir -p "$INSTALL_DIR"

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
    echo "0 0 * * * $INSTALL_DIR/test_script.sh >/dev/null"
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

@test "Component: OS Update - Uses native package upgrade" {
    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
if [[ "$*" == *"full-upgrade"* ]]; then echo "SUCCESS_FULL_UPGRADE"; fi
EOF
    /usr/bin/chmod +x "$MOCK_DIR/apt-get"
    cat << 'EOF' > "$MOCK_DIR/dnf"
#!/bin/bash
if [[ "$*" == *"upgrade"* ]]; then echo "SUCCESS_DNF_UPGRADE"; fi
EOF
    /usr/bin/chmod +x "$MOCK_DIR/dnf"
    cat << 'EOF' > "$MOCK_DIR/pacman"
#!/bin/bash
if [[ "$*" == *"-Syu"* ]] || [[ "$*" == *"Syu"* ]]; then echo "SUCCESS_PACMAN_UPGRADE"; fi
echo "[MOCK] pacman $*"
EOF
    /usr/bin/chmod +x "$MOCK_DIR/pacman"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; ./scripts/update_pi_os.sh"
    [[ "$output" =~ "SUCCESS_FULL_UPGRADE" || "$output" =~ "SUCCESS_DNF_UPGRADE" || "$output" =~ "SUCCESS_PACMAN_UPGRADE" || "$output" =~ "dnf upgrade" || "$output" =~ "pacman -Syu" || "$output" =~ "apt-get full-upgrade" ]]
}

@test "Component: OS Update - missing mail helper fails visibly" {
    run bash -c "export PATH=$MOCK_DIR:\$PATH; source ./scripts/update_pi_os.sh; unset -f send_mail; main"
    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "mail helper" ]]
}

@test "Component: Docker Cleanup - missing mail helper fails visibly" {
    run bash -c "export PATH=$MOCK_DIR:\$PATH; source ./scripts/docker_cleanup.sh; unset -f send_mail; main"
    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "mail helper" ]]
}

@test "Component: Pi Apps - missing mail helper fails visibly" {
    run bash -c "export PATH=$MOCK_DIR:\$PATH; source ./scripts/update_pi_apps.sh; unset -f send_mail; main"
    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "mail helper" ]]
}

@test "Component: Samsung - missing mail helper fails visibly" {
    run bash -c "export PATH=$MOCK_DIR:\$PATH; source ./scripts/update_samsung_ssd.sh; unset -f send_mail; main"
    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "mail helper" ]]
}

@test "Component: OS Update - mail send failure warns" {
    cat << 'EOF' > "$MOCK_DIR/ssmtp"
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_DIR/ssmtp"
    rm -f "$MOCK_DIR/msmtp"
    echo "root=admin@test.com" > "$SSMTP_CONF"
    run bash -c "export PATH=$MOCK_DIR:\$PATH SSMTP_CONF=$SSMTP_CONF; ./scripts/update_pi_os.sh"
    [[ "$output" =~ "failed to deliver email" || "$output" =~ "WARNING" ]]
}

@test "Component: OS Update - Detects Reboot Required (Negative)" {

    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
echo "Doing nothing"
EOF
    /usr/bin/chmod +x "$MOCK_DIR/apt-get"
    /usr/bin/chmod +x "$MOCK_DIR/apt-get"
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
    /usr/bin/chmod +x "$MOCK_DIR/apt-get"
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

@test "Component: Docker Cleanup - install-dir lib layout" {
    local staged="$MOCK_DIR/staged_docker"
    rm -rf "$staged"
    mkdir -p "$staged/lib"
    cp ./scripts/docker_cleanup.sh "$staged/"
    cp ./lib/*.sh "$staged/lib/"

    cat << 'EOF' > "$MOCK_DIR/docker"
#!/bin/bash
if [[ "$1" == "buildx" && "$2" == "version" ]]; then exit 0;
elif [[ "$1" == "buildx" && "$2" == "prune" ]]; then echo "BUILDX_PRUNE_CALLED";
fi
EOF
    chmod +x "$MOCK_DIR/docker"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; \"$staged/docker_cleanup.sh\""
    [[ "$output" =~ "BUILDX_PRUNE_CALLED" ]]
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
    # Use a writable temp HOME (bind-mounted repo HOME may not be writable in containers).
    local pi_apps_home
    pi_apps_home=$(mktemp -d)
    mkdir -p "$pi_apps_home/pi-apps"
    cat << 'EOF' > "$pi_apps_home/pi-apps/updater"
#!/bin/bash
echo "cli-yes"
EOF
    /usr/bin/chmod +x "$pi_apps_home/pi-apps/updater"

    cat << 'EOF' > "$MOCK_DIR/ssmtp"
#!/bin/bash
echo "EMAIL_SENT_HEADER"
cat
EOF
    chmod +x "$MOCK_DIR/ssmtp"

    run bash -c "export PATH=$MOCK_DIR:\$PATH HOME=$pi_apps_home; ./scripts/update_pi_apps.sh"
    [[ "$output" =~ "cli-yes" ]]
    [[ "$output" =~ "EMAIL_SENT_HEADER" ]]
    rm -rf "$pi_apps_home"
}

@test "Component: Pi-Apps - Updater Missing" {

    # Ensure updater is MISSING
    SETUP_CMD='export HOME="$MOCK_DIR"; mkdir -p "$HOME/pi-apps"; rm -f "$HOME/pi-apps/updater"; '
    
    run bash -c "${SETUP_CMD} export PATH=$MOCK_DIR:$PATH; export HOME=$MOCK_DIR; ./scripts/update_pi_apps.sh"
    [[ "$output" =~ "Pi-Apps updater not found" ]]
}

@test "Component: Pi-Apps - install-dir lib layout" {
    local staged="$MOCK_DIR/staged_pi_apps"
    local pi_apps_home
    rm -rf "$staged"
    mkdir -p "$staged/lib"
    cp ./scripts/update_pi_apps.sh "$staged/"
    cp ./lib/*.sh "$staged/lib/"

    pi_apps_home=$(mktemp -d)
    mkdir -p "$pi_apps_home/pi-apps"
    cat << 'EOF' > "$pi_apps_home/pi-apps/updater"
#!/bin/bash
echo "cli-yes"
EOF
    /usr/bin/chmod +x "$pi_apps_home/pi-apps/updater"

    cat << 'EOF' > "$MOCK_DIR/ssmtp"
#!/bin/bash
echo "EMAIL_SENT_HEADER"
cat
EOF
    chmod +x "$MOCK_DIR/ssmtp"

    run bash -c "export PATH=$MOCK_DIR:\$PATH HOME=$pi_apps_home; \"$staged/update_pi_apps.sh\""
    [[ "$output" =~ "cli-yes" ]]
    rm -rf "$pi_apps_home"
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
elif [[ "$1" == "get-upgrades" ]]; then
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
if [[ "$1" == "refresh" ]]; then
    exit 0
elif [[ "$1" == "get-upgrades" ]]; then
    echo "No upgrades for any device"
    exit 0
elif [[ "$1" == "get-updates" ]]; then
    echo "No updates for any device"
    exit 0
fi
EOF
    /bin/chmod +x "$MOCK_DIR/fwupdmgr"
    
    cat << 'EOF' > "$MOCK_DIR/shutdown"
#!/bin/bash
echo "FAIL_SHOULD_NOT_REBOOT"
EOF
    chmod +x "$MOCK_DIR/shutdown"

    run bash -c "export PATH=$MOCK_DIR:$PATH; ./scripts/update_pi_firmware.sh"
    
    [[ "$output" =~ "No updates available" || "$output" =~ "No upgrades available" ]]
    [[ ! "$output" =~ "FAIL_SHOULD_NOT_REBOOT" ]]
}

@test "Component: Firmware - Automatic Dependency Installation" {
    # Ensure neither rpi-eeprom-update nor fwupdmgr are in PATH/MOCK_DIR
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    rm -f "$MOCK_DIR/fwupdmgr"

    # Force non-Pi detection via a temporary grep ahead of mocks (do not clobber MOCK_DIR/grep).
    local grephome
    grephome=$(mktemp -d)
    cat << 'EOF' > "$grephome/grep"
#!/bin/bash
if [[ "$*" == *"Raspberry Pi"* ]]; then
    exit 1
fi
exec /usr/bin/grep "$@"
EOF
    /usr/bin/chmod +x "$grephome/grep"

    # Mock package managers to show installation attempt
    for mgr in apt-get dnf yum pacman; do
        cat << EOF > "$MOCK_DIR/$mgr"
#!/bin/bash
if [[ "\$*" == *"install"* ]] || [[ "\$1" == "-S" ]] || [[ "\$*" == *"-S "* ]]; then
    echo "INSTALL_CALLED_FOR: \$@"
    echo "#!/bin/bash" > "$MOCK_DIR/fwupdmgr"
    echo "echo 'MOCKED FWUPDMGR'" >> "$MOCK_DIR/fwupdmgr"
    /usr/bin/chmod +x "$MOCK_DIR/fwupdmgr"
fi
exit 0
EOF
        /usr/bin/chmod +x "$MOCK_DIR/$mgr"
    done

    run bash -c "export PATH=$grephome:$MOCK_DIR:\$PATH; ./scripts/update_pi_firmware.sh"
    rm -rf "$grephome"

    [[ "$output" =~ "Dependencies installed successfully" ]]
    [[ "$output" =~ "Running 'fwupdmgr'" || "$output" =~ "Running 'sudo rpi-eeprom-update" ]]
}

@test "Component: Firmware - Automatic Dependency Failure" {
    # Ensure neither rpi-eeprom-update nor fwupdmgr are in PATH/MOCK_DIR
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    rm -f "$MOCK_DIR/fwupdmgr"
    local clean_path=""
    local dir
    IFS=':' read -r -a _path_parts <<< "$PATH"
    for dir in "${_path_parts[@]}"; do
        [ -x "${dir}/fwupdmgr" ] && continue
        [ -x "${dir}/rpi-eeprom-update" ] && continue
        clean_path="${clean_path:+$clean_path:}$dir"
    done

    # Mock package-manager install failure for all families
    for mgr in apt-get dnf yum pacman; do
        cat << 'EOF' > "$MOCK_DIR/$mgr"
#!/bin/bash
if [[ "$*" == *"install"* ]] || [[ "$*" == *"-S "* ]] || [[ "$1" == "-S" ]]; then
    exit 1
fi
exit 0
EOF
        /usr/bin/chmod +x "$MOCK_DIR/$mgr"
    done

    run bash -c "export PATH=$MOCK_DIR:$clean_path; ./scripts/update_pi_firmware.sh"

    [[ "$output" =~ "Warning: Some dependencies may have failed to install" || "$output" =~ "no package mapping" || "$output" =~ "No package mapping" ]]
}
@test "Component: Install - Version Tracking" {
    # install_lib is sourced from MOCK_DIR; stage VERSION there as the SSOT.
    echo "v1.1.0" > "$MOCK_DIR/VERSION"

    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$*" =~ "scripts/test_script.sh" ]]; then
    touch "$INSTALL_DIR/test_script.sh"
fi
EOF
    chmod +x "$MOCK_DIR/curl"

    mkdir -p "$(dirname "$SSMTP_CONF")"
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    mkdir -p "$INSTALL_DIR"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source \"$MOCK_DIR/install_lib.sh\"; SCRIPTS[1]='test_script.sh'; download_scripts"

    [[ -f "$INSTALL_DIR/.version" ]]
    [[ "$(cat "$INSTALL_DIR/.version")" == "v1.1.0" ]]
    [[ "$output" =~ "Version set to: v1.1.0" ]]
}

@test "Component: Install - lib download HTTP failure is reported" {
    rm -rf "$MOCK_DIR/lib"
    mkdir -p "$INSTALL_DIR"
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$*" == *"/lib/"* ]]; then
    exit 22
fi
if [[ "$*" == *"/VERSION"* ]]; then
    echo "v1.1.0"
    exit 0
fi
outfile=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then outfile="$a"; fi
  prev="$a"
done
[ -n "$outfile" ] && touch "$outfile"
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"

    run bash -c "export PATH=$MOCK_DIR:$PATH; source \"$MOCK_DIR/install_lib.sh\"; SCRIPTS[1]='test_script.sh'; download_scripts"
    [[ "$output" =~ "Error downloading lib/" ]]
}

@test "Component: Install - Version Tracking via RAW_URL fallback" {
    # No local VERSION next to install_lib → fetch from RAW_URL/VERSION (ignore stale .version)
    rm -f "$MOCK_DIR/VERSION"
    rm -f "$INSTALL_DIR/.version"
    unset SUITE_VERSION
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$*" == *"/VERSION"* ]]; then
    echo "v1.0.2"
    exit 0
elif [[ "$*" =~ "scripts/test_script.sh" ]]; then
    touch "$INSTALL_DIR/test_script.sh"
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"

    mkdir -p "$(dirname "$SSMTP_CONF")"
    echo "AuthUser=existing@test.com" > "$SSMTP_CONF"
    mkdir -p "$INSTALL_DIR"

    run bash -c "export PATH=$MOCK_DIR:$PATH; unset SUITE_VERSION; source \"$MOCK_DIR/install_lib.sh\"; SCRIPTS[1]='test_script.sh'; download_scripts"

    [[ -f "$INSTALL_DIR/.version" ]]
    [[ "$(cat "$INSTALL_DIR/.version")" == "v1.0.2" ]]
    [[ "$output" =~ "Version set to: v1.0.2" ]]
}

@test "Component: Install - print_header shows suite version" {
    echo "v1.1.0" > "$MOCK_DIR/VERSION"
    unset SUITE_VERSION

    run bash -c "export PATH=$MOCK_DIR:$PATH; unset SUITE_VERSION; source \"$MOCK_DIR/install_lib.sh\"; print_header"

    [[ "$output" =~ "Raspberry Pi Maintenance Suite Manager" ]]
    [[ "$output" =~ "v1.1.0" ]]
}

@test "Component: Install - _pi_task_name covers firmware pip and unknown" {
    # Source the real install.sh so kcov attributes hits to install.sh (not install_lib.sh).
    run bash -c '
        source ./install.sh
        _pi_task_name 2
        echo
        _pi_task_name 3
        echo
        _pi_task_name 99
        echo
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Firmware Update"* ]]
    [[ "$output" == *"Python Pip Update"* ]]
    [[ "$output" == *"Unknown task"* ]]
}

@test "Component: Pip - No outdated packages (install-dir lib layout)" {
    local staged="$MOCK_DIR/staged_pip"
    rm -rf "$staged"
    mkdir -p "$staged/lib"
    cp ./scripts/update_pip.sh "$staged/"
    cp ./lib/*.sh "$staged/lib/"

    cat << 'EOF' > "$MOCK_DIR/pip3"
#!/bin/bash
if [[ "$*" == *"list"* ]]; then
    echo "Package Version Latest Type"
    echo "------- ------- ------ ----"
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/pip3"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; \"$staged/update_pip.sh\""
    [[ "$output" =~ "All pip3 packages are up-to-date" ]]
}

@test "Component: Firmware - get-upgrades fails then get-updates succeeds" {
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    cat << 'EOF' > "$MOCK_DIR/fwupdmgr"
#!/bin/bash
if [[ "$1" == "refresh" ]]; then
    exit 0
elif [[ "$1" == "get-upgrades" ]]; then
    echo "get-upgrades unavailable"
    exit 1
elif [[ "$1" == "get-updates" ]]; then
    echo "Device has update"
    exit 0
elif [[ "$1" == "update" ]]; then
    echo "Update applied without reboot keywords"
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/fwupdmgr"
    cat << 'EOF' > "$MOCK_DIR/shutdown"
#!/bin/bash
echo "FAIL_SHOULD_NOT_REBOOT"
EOF
    chmod +x "$MOCK_DIR/shutdown"

    local staged="$MOCK_DIR/staged_fw"
    rm -rf "$staged"
    mkdir -p "$staged/lib"
    cp ./scripts/update_pi_firmware.sh "$staged/"
    cp ./lib/*.sh "$staged/lib/"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; \"$staged/update_pi_firmware.sh\""
    [[ "$output" =~ "Updates available" || "$output" =~ "Device has update" ]]
    [[ ! "$output" =~ "FAIL_SHOULD_NOT_REBOOT" ]]
}

@test "Component: Firmware - fwupdmgr query failure path" {
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    cat << 'EOF' > "$MOCK_DIR/fwupdmgr"
#!/bin/bash
if [[ "$1" == "refresh" ]]; then exit 0; fi
exit 1
EOF
    chmod +x "$MOCK_DIR/fwupdmgr"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; ./scripts/update_pi_firmware.sh"
    [[ "$output" =~ "failed to query update availability" ]]
}
