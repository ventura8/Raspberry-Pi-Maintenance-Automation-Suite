#!/usr/bin/env bats

# Whiptail UI path + text-fallback coverage for install.sh

setup() {
    export MOCK_DIR="/tmp/mocks"
    export INSTALL_DIR="/tmp/scripts_whiptail"
    rm -rf "$INSTALL_DIR"
    export SSMTP_CONF="/tmp/ssmtp_whiptail.conf"
    export REVALIASES="/tmp/revaliases_whiptail"
    export TEST_MODE="true"
    export INSTALL_USE_WHIPTAIL="1"
    export INSTALL_FORCE_TEXT_UI="0"

    ./tests/setup_mocks.sh > /dev/null
    export PATH="$MOCK_DIR:$PATH"

    > "$SSMTP_CONF"
    > "$REVALIASES"
    echo "auto" > "$MOCK_DIR/whiptail_mode"
    echo "yes" > "$MOCK_DIR/whiptail_yesno"
    : > "$MOCK_DIR/whiptail_input"
    : > "$MOCK_DIR/whiptail_checklist"

    export TEST_WORKSPACE
    TEST_WORKSPACE=$(mktemp -d)
    cp ./install.sh "$TEST_WORKSPACE/"
    mkdir -p "$TEST_WORKSPACE/lib"
    cp ./lib/*.sh "$TEST_WORKSPACE/lib/"
    cp ./VERSION "$TEST_WORKSPACE/" 2> /dev/null || printf 'v1.1.0\n' > "$TEST_WORKSPACE/VERSION"
    cd "$TEST_WORKSPACE"
}

teardown() {
    cd / > /dev/null || true
    rm -rf "${TEST_WORKSPACE:-}"
}

@test "Whiptail: Fresh install enables selected tasks then exits menu" {
    printf '%s\n' "yes" "yes" > "$MOCK_DIR/whiptail_yesno"
    printf '%s\n' "whip@test.com" "apppassword" "0" > "$MOCK_DIR/whiptail_input"
    printf '%s\n' "1" "4" "7" > "$MOCK_DIR/whiptail_checklist"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        source ./install.sh; run_fresh_install"

    [[ "$output" =~ "Suite version: v1.1.0" || "$output" =~ "v1.1.0" ]]
    [[ "$output" =~ "Email configured successfully" ]]
    [[ "$output" =~ "Enabled System OS Update" ]]
    [[ "$output" =~ "Enabled Docker Cleanup" ]]
    [[ "$output" =~ "Enabled Self-Update Service" ]]

    run cat "$MOCK_DIR/root_cron"
    [[ "$output" =~ "update_pi_os.sh" ]]
    [[ "$output" =~ "docker_cleanup.sh" ]]
    [[ "$output" =~ "update_self.sh" ]]
}

@test "Whiptail: Cancel on welcome aborts install" {
    printf '%s\n' "no" > "$MOCK_DIR/whiptail_yesno"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        source ./install.sh; run_fresh_install; echo RC=\$?"

    [[ "$output" =~ "Installation cancelled before setup" ]]
    [[ "$output" =~ "RC=1" ]]
    [[ ! -d "$INSTALL_DIR" ]]
}

@test "Whiptail: Cancel before download aborts without installing scripts" {
    printf '%s\n' "yes" "no" > "$MOCK_DIR/whiptail_yesno"
    printf '%s\n' "whip@test.com" "apppassword" > "$MOCK_DIR/whiptail_input"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        source ./install.sh; run_fresh_install; echo RC=\$?"

    [[ "$output" =~ "Installation cancelled before downloading scripts" ]]
    [[ "$output" =~ "RC=1" ]]
    [[ ! -f "$INSTALL_DIR/.version" ]]
}

@test "Whiptail: Cancel on task checklist aborts with message" {
    printf '%s\n' "yes" "yes" > "$MOCK_DIR/whiptail_yesno"
    printf '%s\n' "whip@test.com" "apppassword" > "$MOCK_DIR/whiptail_input"

    run bash -c "
        export PATH=$MOCK_DIR:\$PATH INSTALL_USE_WHIPTAIL=1
        source ./install.sh
        download_scripts() {
            mkdir -p \"\$INSTALL_DIR\"
            printf '%s\n' 'v1.1.0' > \"\$INSTALL_DIR/.version\"
        }
        _enable_selected_fresh_tasks_whiptail() { return 1; }
        run_fresh_install_whiptail
        echo RC=\$?
    "

    [[ "$output" =~ "Installation cancelled during task selection" ]]
    [[ "$output" =~ "RC=1" ]]
}

@test "Whiptail: Checklist Esc/Cancel returns abort status" {
    echo "cancel" > "$MOCK_DIR/whiptail_mode"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        source ./install.sh; select_ui_mode; _enable_selected_fresh_tasks_whiptail; echo RC=\$?"

    [[ "$output" =~ "RC=1" ]]
}

@test "Whiptail: Main menu configure email and exit" {
    mkdir -p "$INSTALL_DIR"
    printf '%s\n' "1" "menu@test.com" "secretpass" "0" > "$MOCK_DIR/whiptail_input"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        source ./install.sh; main_menu"

    [[ "$output" =~ "Email configured successfully" ]]
    run grep "^AuthUser=" "$SSMTP_CONF"
    [[ "$output" == "AuthUser=menu@test.com" ]]
}

@test "Whiptail: Hard dialog failure falls back to text UI" {
    echo "fail" > "$MOCK_DIR/whiptail_mode"
    rm -f "$SSMTP_CONF"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        export SSMTP_CONF=$SSMTP_CONF; \
        source ./install.sh; configure_email_interactive" <<< $'fallback@test.com\npassword'

    [[ "$output" =~ "switching to text interface" ]]
    [[ "$output" =~ "Email configured successfully" ]]
}

@test "Whiptail: Cancel on email dialog aborts without text fallback" {
    echo "cancel" > "$MOCK_DIR/whiptail_mode"
    rm -f "$SSMTP_CONF"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        export SSMTP_CONF=$SSMTP_CONF; \
        source ./install.sh; configure_email_interactive; echo RC=\$?"

    [[ "$output" =~ "RC=1" ]]
    [[ ! "$output" =~ "Enter Gmail address" ]]
}

@test "Text fallback: INSTALL_FORCE_TEXT_UI bypasses whiptail" {
    printf '%s\n' "should-not-be-read" > "$MOCK_DIR/whiptail_input"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        export INSTALL_FORCE_TEXT_UI=1; \
        source ./install.sh; configure_email_interactive <<< $'Y\ntext@test.com\npassword'"

    [[ "$output" =~ "Enter Gmail address" ]]
    [[ "$output" =~ "Email configured successfully" ]]
    [[ ! "$output" =~ "switching to text interface" ]]
}

@test "Dependencies: installs whiptail when missing" {
    run bash -c "
        export PATH=$MOCK_DIR:\$PATH
        source ./install.sh
        is_installed() {
            if [[ \"\$1\" == \"whiptail\" ]]; then return 1; fi
            command -v \"\$1\" &> /dev/null
        }
        check_dependencies
    "
    [[ "$output" =~ "whiptail not found. Installing whiptail" ]]
}

@test "Whiptail: Task manager can enable a disabled task" {
    rm -f "$MOCK_DIR/root_cron"
    # menu select task 1, yesno enable, inputbox schedule, menu return 0
    printf '%s\n' "1" "0 0 * * *" "0" > "$MOCK_DIR/whiptail_input"
    echo "yes" > "$MOCK_DIR/whiptail_yesno"

    run bash -c "export PATH=$MOCK_DIR:\$PATH; export INSTALL_USE_WHIPTAIL=1; \
        source ./install.sh; manage_tasks_ui"

    [[ "$output" =~ "Task enabled" ]]
    run cat "$MOCK_DIR/root_cron"
    [[ "$output" =~ "update_pi_os.sh" ]]
}
