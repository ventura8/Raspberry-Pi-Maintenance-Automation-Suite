#!/usr/bin/env bats
# E2E checks for REAL_DEPS=1 distro matrix lanes (real packages; HW mocked).

setup() {
    export TEST_MODE=true
    export REAL_DEPS=1
    export INSTALL_FORCE_TEXT_UI=1
    export MATRIX_ALLOW_RM_INSTALL_DIR=1
    export INSTALL_DIR="/tmp/pi-scripts-e2e-bats-$$"
    rm -rf "$INSTALL_DIR"
    # shellcheck source=../setup_mocks.sh
    source ./tests/setup_mocks.sh
    # shellcheck source=../../scripts/matrix_install_flow.sh
    source ./scripts/matrix_install_flow.sh
}

teardown() {
    rm -rf "$INSTALL_DIR"
}

@test "os_pkg detects a supported family" {
    # shellcheck source=../../lib/os_pkg.sh
    source ./lib/os_pkg.sh
    family=$(detect_os_family)
    [[ "$family" == "debian" || "$family" == "redhat" || "$family" == "arch" ]]
}

@test "install.sh --update installs scripts and lib helpers" {
    run bash ./install.sh --update
    [ "$status" -eq 0 ]
    [ -f "$INSTALL_DIR/update_pi_os.sh" ]
    [ -f "$INSTALL_DIR/lib/os_pkg.sh" ]
    [ -f "$INSTALL_DIR/lib/mail_send.sh" ]
    [ -f "$INSTALL_DIR/.version" ]
}

@test "text fresh install then uninstall removes INSTALL_DIR" {
    matrix_prepare_install_env
    matrix_run_text_fresh_install "e2e-bats@example.com" "app-password-test"
    matrix_assert_installed
    matrix_run_uninstall
    [ ! -d "$INSTALL_DIR" ]
}

@test "pkg_update_system function exists for current family" {
    # shellcheck source=../../lib/os_pkg.sh
    source ./lib/os_pkg.sh
    type pkg_update_system | grep -q function
}
