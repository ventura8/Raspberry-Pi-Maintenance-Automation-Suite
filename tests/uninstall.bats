#!/usr/bin/env bats

# Tests for uninstall.sh

setup() {
    export MOCK_DIR="/tmp/mocks"
    export INSTALL_DIR="/tmp/scripts" # Matches default mock
    
    # Always ensure clean shared mocks
    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"
    
    # Create mock install directory
    mkdir -p "$INSTALL_DIR"
    touch "$INSTALL_DIR/update_pi_os.sh"
    touch "$INSTALL_DIR/update_pi_apps.sh"
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
        echo "0 0 * * * /tmp/scripts/update_pi_os.sh"
        echo "0 1 * * * /tmp/scripts/update_pi_firmware.sh"
        echo "0 2 * * * /usr/bin/root_job"
    else
        # User Crontab Entries
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
    cat >> "/tmp/mocks/crontab_written"
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
        
        # Verify User Section
        [[ "$output" =~ "user_job" ]]
        [[ "$output" != *"update_pi_apps.sh"* ]]
    fi
}

@test "Uninstall: Entry Point (Direct Execution)" {
    # This tests the "if [[ -z ... ]]" block at the end
    # We rely on the fact that running it via BATS 'run' executes it as a script, 
    # but we need to ensure the logic triggers 'main'
    
    run bash ./uninstall.sh
    [[ "$output" =~ "RPi Maintenance Suite Uninstaller" ]]
}
