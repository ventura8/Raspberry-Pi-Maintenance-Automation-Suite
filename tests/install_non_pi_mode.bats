#!/usr/bin/env bats

setup() {
    export MOCK_DIR="/tmp/mocks"
    export INSTALL_DIR="/tmp/scripts_non_pi"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$MOCK_DIR"
    mkdir -p "$INSTALL_DIR"

    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"
}

@test "Install: Hardware Detection - Non-Pi Mode" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; export TEST_MODE=true; export MOCK_IS_PI=false; source ./install.sh; echo \"IS_PI: \$IS_PI\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "IS_PI: false" ]]
}

@test "Install: Download Scripts - Non-Pi (Includes Firmware, Skips Pip)" {
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
outfile=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then outfile="$2"; fi
  shift
done
touch "$outfile"
exit 0
EOF
    chmod +x "$MOCK_DIR/curl"

    run bash -c "export PATH=$MOCK_DIR:$PATH; export TEST_MODE=true; export MOCK_IS_PI=false; export INSTALL_DIR=$INSTALL_DIR; source ./install.sh; download_scripts"
    [ "$status" -eq 0 ]

    [[ -f "$INSTALL_DIR/update_pi_firmware.sh" ]]
    [[ ! -f "$INSTALL_DIR/update_pip.sh" ]]
    [[ "$output" =~ "Scripts updated" ]]
}

@test "Install: Manager UI - Non-Pi (Shows Firmware, Hides Pip)" {
    run bash -c "export PATH=$MOCK_DIR:$PATH; export TEST_MODE=true; export MOCK_IS_PI=false; source ./install.sh; manage_tasks_ui <<< '0'"
    [ "$status" -eq 0 ]

    [[ "$output" =~ "Firmware Update" ]]
    [[ ! "$output" =~ "Python Pip Update" ]]
}

@test "Install: Run Enabled Tasks Now - Non-Pi Skips Pip Task" {
    rm -f "$MOCK_DIR/root_cron" "$MOCK_DIR/user_cron"

    cat << 'EOF' > "$INSTALL_DIR/update_pip.sh"
#!/bin/bash
echo "RUN_PIP_SHOULD_NOT_HAPPEN"
EOF
    chmod +x "$INSTALL_DIR/update_pip.sh"

    echo "0 4 * * 0 $INSTALL_DIR/update_pip.sh >/dev/null" > "$MOCK_DIR/root_cron"

    run bash -c "export PATH=$MOCK_DIR:$PATH; export TEST_MODE=true; export MOCK_IS_PI=false; export INSTALL_DIR=$INSTALL_DIR; source ./install.sh; run_enabled_tasks_now <<< $'\\n'"
    [ "$status" -eq 0 ]

    [[ "$output" =~ "No enabled tasks found" ]]
    [[ ! "$output" =~ "RUN_PIP_SHOULD_NOT_HAPPEN" ]]
}
