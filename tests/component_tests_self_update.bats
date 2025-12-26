#!/usr/bin/env bats

setup() {
    export MOCK_DIR="/tmp/mocks"
    # Use nested dir in tmp to avoid volume permission issues AND overwrites
    export TEST_ROOT="/tmp/test_env"
    export INSTALL_DIR="$TEST_ROOT/scripts"
    mkdir -p "$MOCK_DIR"
    mkdir -p "$INSTALL_DIR"
    
    # Setup Mocks
    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"
    
    # Mock install.sh
    echo "#!/bin/bash" > "$INSTALL_DIR/../install.sh"
    echo "echo 'Mock Install Script Ran'" >> "$INSTALL_DIR/../install.sh"
    chmod +x "$INSTALL_DIR/../install.sh"
}

@test "Self Update: No Update Needed" {
    # Setup
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.0.0"
    
    # Mock Curl to return JSON with TAG
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$@" == *"api.github.com"* ]]; then
    # Return mock release JSON
    echo "{\"tag_name\": \"$TEST_REMOTE_TAG\"}"
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"
    
    # Mock ssmtp for email recipient
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh
    
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "System is up to date" ]]
    [[ "$output" =~ "Sending email to mock_admin@test.com" ]]
}

@test "Self Update: Update Available (Test Mode)" {
    # Setup
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.1.0"
    
    # Mock Curl
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$@" == *"api.github.com"* ]]; then
    echo "{\"tag_name\": \"$TEST_REMOTE_TAG\"}"
    exit 0
elif [[ "$@" == *"install.sh"* ]]; then
         exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"
    
    # Mock ssmtp for email recipient
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    export TEST_MODE="true"
    run ./scripts/update_self.sh
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Update available" ]]
    [[ "$output" =~ "TEST_MODE: Skipping actual execution" ]]
    # Ensure success email is sent even in test mode
    [[ "$output" =~ "Sending email to mock_admin@test.com" ]]
    [[ "$(cat $INSTALL_DIR/.version)" == "v1.1.0" ]]
}

@test "Self Update: Real Execution" {
    # Setup
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.2.0"
    unset TEST_MODE
    
    # Mock Curl
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$@" == *"api.github.com"* ]]; then
    echo "{\"tag_name\": \"$TEST_REMOTE_TAG\"}"
    exit 0
elif [[ "$@" == *"install.sh"* ]]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"

    # Mock install.sh to consume input and verify
    cat << 'EOF' > "$INSTALL_DIR/../install.sh"
#!/bin/bash
echo "MOCK_INSTALLER_STARTED"
read -t 1 line
echo "INSTALLER_EXECUTED_CORRECTLY"
EOF
    chmod +x "$INSTALL_DIR/../install.sh"
    
    # Mock ssmtp for email recipient
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh
    
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "INSTALLER_EXECUTED_CORRECTLY" ]]
    [[ "$output" =~ "Update complete" ]]
    [[ "$output" =~ "Sending email to mock_admin@test.com" ]]
    [[ "$(cat $INSTALL_DIR/.version)" == "v1.2.0" ]]
}

@test "Self Update: API Failure" {
    export TEST_REMOTE_TAG="fail"
    
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"
    
    # Mock ssmtp for email recipient (expect failure notification)
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"
    
    run ./scripts/update_self.sh
    
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Error: Failed to contact GitHub API" ]]
    [[ "$output" =~ "Sending email to mock_admin@test.com" ]]
}

@test "Self Update: Malformed Response" {
    # Returns empty JSON
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
echo "{}"
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"
    
    # Mock ssmtp for email recipient
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh
    
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Could not parse remote tag" ]]
    [[ "$output" =~ "Sending email to mock_admin@test.com" ]]
}
