#!/usr/bin/env bats

setup() {
    export MOCK_DIR="/tmp/mocks"
    export INSTALL_DIR="/tmp/scripts"
    mkdir -p "$MOCK_DIR"
    mkdir -p "$INSTALL_DIR"
    
    # Setup Mocks
    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"
    
    # install.sh checks /proc or uses MOCK_IS_PI if TEST_MODE is true
    # We will use MOCK_IS_PI to avoid mocking grep which breaks BATS
}

@test "Install: Hardware Detection - Raspberry Pi Mode" {
    # Source install.sh with MOCK_IS_PI=true
    run bash -c "export PATH=$MOCK_DIR:$PATH; export TEST_MODE=true; export MOCK_IS_PI=true; source ./install.sh; echo \"IS_PI: \$IS_PI\""
    [[ "$output" =~ "IS_PI: true" ]]
}

@test "Install: Download Scripts - Pi Mode (Includes Firmware/Pip)" {
    export PATH="$MOCK_DIR:$PATH"
    
    # Mock curl to just touch files
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

    run bash -c "export PATH=$MOCK_DIR:$PATH; export TEST_MODE=true; export MOCK_IS_PI=true; source ./install.sh; download_scripts"
    
    # In Pi Mode, it should NOT skip firmware/pip
    # We check if it attempted to download them. 
    # download_scripts calls curl ... -o .../$script
    # We check if files exist in INSTALL_DIR
    
    [[ -f "$INSTALL_DIR/update_pi_firmware.sh" ]]
    [[ -f "$INSTALL_DIR/update_pip.sh" ]]
    [[ "$output" =~ "Scripts updated" ]]
}

@test "Install: Manager UI - Pi Mode (Shows All Tasks)" {
    export PATH="$MOCK_DIR:$PATH"
    
    # We run manage_tasks_ui and check output for Firmware/Pip
    # Input 0 to exit immediately
    
    run bash -c "export PATH=$MOCK_DIR:$PATH; export TEST_MODE=true; export MOCK_IS_PI=true; source ./install.sh; manage_tasks_ui <<< '0'"
    
    [[ "$output" =~ "Firmware Update" ]]
    [[ "$output" =~ "Python Pip Update" ]]
}
