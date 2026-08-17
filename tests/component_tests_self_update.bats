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
    
    # Mock install.sh is no longer written next to INSTALL_DIR; staging uses mktemp.
}

# Shared curl mock helper body: GitHub API + tagged install.sh + VERSION staging.
# Writes TEST_REMOTE_TAG into -o path when VERSION is requested.
_mock_curl_self_update() {
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$@" == *"api.github.com"* ]]; then
    echo "{\"tag_name\": \"$TEST_REMOTE_TAG\"}"
    exit 0
fi

out=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "-o" ]; then
        out="$arg"
    fi
    prev="$arg"
done

if [[ "$@" == *"install.sh"* ]]; then
    if [ -n "$out" ]; then
        cat << 'INSTALLER' > "$out"
#!/bin/bash
echo "TAGGED_INSTALLER_EXECUTED"
echo "RAW_URL=${RAW_URL:-unset}"
if [[ "$1" == "--update" ]]; then
    echo "INSTALLER_EXECUTED_CORRECTLY"
    exit 0
fi
exit 0
INSTALLER
        chmod +x "$out"
    fi
    exit 0
fi

if [[ "$@" == *"/lib/"* ]]; then
    if [ -n "$out" ]; then
        printf '%s\n' "# staged lib stub" > "$out"
    fi
    exit 0
fi

if [[ "$@" == *VERSION* ]]; then
    if [ -n "$out" ]; then
        printf '%s\n' "$TEST_REMOTE_TAG" > "$out"
    else
        printf '%s\n' "$TEST_REMOTE_TAG"
    fi
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"
}

@test "Self Update: No Update Needed" {
    # Setup
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.0.0"

    _mock_curl_self_update

    # Mock ssmtp for email recipient
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "System is up to date" ]]
    [[ "$output" =~ "Email notification delivered to mock_admin@test.com" ]]
}

@test "Self Update: Update Available (Test Mode)" {
    # Setup
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.1.0"

    _mock_curl_self_update

    # Mock ssmtp for email recipient
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    export TEST_MODE="true"
    run ./scripts/update_self.sh
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Update available" ]]
    [[ "$output" =~ "TEST_MODE: Skipping actual execution" ]]
    # Ensure success email is sent even in test mode
    [[ "$output" =~ "Email notification delivered to mock_admin@test.com" ]]
    [[ "$(cat $INSTALL_DIR/.version)" == "v1.1.0" ]]
}

@test "Self Update: Real Execution" {
    # Setup
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.2.0"
    unset TEST_MODE

    _mock_curl_self_update

    # Pre-seed a stale parent-dir installer that must not be used.
    cat << 'EOF' > "$INSTALL_DIR/../install.sh"
#!/bin/bash
echo "STALE_LOCAL_INSTALLER"
exit 1
EOF
    chmod +x "$INSTALL_DIR/../install.sh"

    # Mock ssmtp for email recipient
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "TAGGED_INSTALLER_EXECUTED" ]]
    [[ "$output" =~ "INSTALLER_EXECUTED_CORRECTLY" ]]
    [[ "$output" =~ "Update complete" ]]
    [[ "$output" =~ "Email notification delivered to mock_admin@test.com" ]]
    [[ "$output" =~ "RAW_URL=https://raw.githubusercontent.com/ventura8/Raspberry-Pi-Maintenance-Automation-Suite/v1.2.0" ]]
    [[ ! "$output" =~ "STALE_LOCAL_INSTALLER" ]]
    [[ "$(cat $INSTALL_DIR/.version)" == "v1.2.0" ]]
}

@test "Self Update: No TTY interaction (Cron regression)" {
    # Regression test: update_self.sh must NOT pipe input into install.sh.
    # Piping caused /dev/tty: No such device or address when run from cron.
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.3.0"
    unset TEST_MODE

    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$@" == *"api.github.com"* ]]; then
    echo "{\"tag_name\": \"$TEST_REMOTE_TAG\"}"
    exit 0
fi
out=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "-o" ]; then out="$arg"; fi
    prev="$arg"
done
if [[ "$@" == *"install.sh"* ]]; then
    cat << 'INSTALLER' > "$out"
#!/bin/bash
if [ ! -t 0 ]; then
    read -t 0.1 stray_input && {
        echo "ERROR: Received unexpected piped input: $stray_input"
        exit 1
    }
fi
echo "INSTALLER_RAN_CLEANLY"
exit 0
INSTALLER
    chmod +x "$out"
    exit 0
fi
if [[ "$@" == *VERSION* ]]; then
    printf '%s\n' "$TEST_REMOTE_TAG" > "$out"
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"

    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "INSTALLER_RAN_CLEANLY" ]]
    [[ ! "$output" =~ "ERROR: Received unexpected piped input" ]]
    [[ "$output" =~ "Email notification delivered to mock_admin@test.com" ]]
}

@test "Self Update: VERSION download failure" {
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.4.0"
    unset TEST_MODE

    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$@" == *"api.github.com"* ]]; then
    echo "{\"tag_name\": \"$TEST_REMOTE_TAG\"}"
    exit 0
elif [[ "$@" == *"install.sh"* ]]; then
    exit 0
elif [[ "$@" == *VERSION* ]]; then
    exit 1
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"

    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Failed to download VERSION" ]]
    [[ "$output" =~ "Email notification delivered to mock_admin@test.com" ]]
}

@test "Self Update: install.sh download failure" {
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.4.1"
    unset TEST_MODE

    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$@" == *"api.github.com"* ]]; then
    echo "{\"tag_name\": \"$TEST_REMOTE_TAG\"}"
    exit 0
elif [[ "$@" == *"install.sh"* ]]; then
    exit 1
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"

    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Failed to download install.sh" ]]
    [[ "$output" =~ "Email notification delivered to mock_admin@test.com" ]]
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
    [[ "$output" =~ "Email notification delivered to mock_admin@test.com" ]]
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
    [[ "$output" =~ "Email notification delivered to mock_admin@test.com" ]]
}

@test "Self Update: Stages installer in mktemp (no parent-dir install.sh required)" {
    rm -f "$INSTALL_DIR/../install.sh"
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.5.0"
    unset TEST_MODE
    _mock_curl_self_update
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "INSTALLER_EXECUTED_CORRECTLY" ]]
    [[ ! -e "$INSTALL_DIR/../install.sh" ]]
    [[ "$(cat $INSTALL_DIR/.version)" == "v1.5.0" ]]
}

@test "Self Update: aborts when staged VERSION mismatches release tag" {
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.5.0"
    unset TEST_MODE
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
if [[ "$@" == *"api.github.com"* ]]; then
    echo "{\"tag_name\": \"$TEST_REMOTE_TAG\"}"
    exit 0
fi
out=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "-o" ]; then out="$arg"; fi
    prev="$arg"
done
if [[ "$@" == *"install.sh"* ]]; then
    [ -n "$out" ] && printf '%s\n' '#!/bin/bash' > "$out" && chmod +x "$out"
    exit 0
fi
if [[ "$@" == *"/lib/"* ]]; then
    [ -n "$out" ] && printf '%s\n' '# stub' > "$out"
    exit 0
fi
if [[ "$@" == *VERSION* ]]; then
    [ -n "$out" ] && printf '%s\n' "v9.9.9" > "$out"
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/curl"
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"

    run ./scripts/update_self.sh
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "does not match release tag" ]]
    [[ "$(cat $INSTALL_DIR/.version)" == "v1.0.0" ]]
}

@test "Self Update: sources libs from sibling lib dir (installed layout)" {
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.0.0"
    _mock_curl_self_update
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    rm -f "$SSMTP_CONF"
    export MSMTP_CONF="$MOCK_DIR/missing-msmtp.conf"

    local staged="$MOCK_DIR/staged_self"
    rm -rf "$staged"
    mkdir -p "$staged/lib"
    cp ./scripts/update_self.sh "$staged/"
    cp ./lib/*.sh "$staged/lib/"

    run bash -c "export PATH=$MOCK_DIR:\$PATH INSTALL_DIR=$INSTALL_DIR SSMTP_CONF=$SSMTP_CONF MSMTP_CONF=$MSMTP_CONF; \"$staged/update_self.sh\""
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "System is up to date" ]]
    [[ "$output" =~ "No mail recipient configured" || "$output" =~ "up to date" ]]
}

@test "Self Update: mail send failure is logged" {
    echo "v1.0.0" > "$INSTALL_DIR/.version"
    export TEST_REMOTE_TAG="v1.0.0"
    _mock_curl_self_update
    export SSMTP_CONF="$MOCK_DIR/ssmtp.conf"
    echo "root=mock_admin@test.com" > "$SSMTP_CONF"
    cat << 'EOF' > "$MOCK_DIR/ssmtp"
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_DIR/ssmtp"
    # Hide msmtp so ssmtp path is chosen then fails
    rm -f "$MOCK_DIR/msmtp"

    run ./scripts/update_self.sh
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Failed to deliver email notification" ]]
}
