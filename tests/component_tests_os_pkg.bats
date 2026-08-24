#!/usr/bin/env bats

setup() {
    source ./tests/setup_mocks.sh
    # shellcheck source=../lib/os_pkg.sh
    source ./lib/os_pkg.sh
    # shellcheck source=../lib/mail_send.sh
    source ./lib/mail_send.sh
}

@test "os_pkg: detect_os_family via INSTALL_OS_ID debian variants" {
    for id in ubuntu debian raspbian linuxmint pop kali elementary; do
        INSTALL_OS_ID="$id" INSTALL_OS_ID_LIKE=""
        run detect_os_family
        [ "$status" -eq 0 ]
        [ "$output" = "debian" ]
    done
}

@test "os_pkg: detect_os_family via INSTALL_OS_ID redhat variants" {
    for id in fedora rhel centos rocky almalinux amzn; do
        INSTALL_OS_ID="$id" INSTALL_OS_ID_LIKE=""
        run detect_os_family
        [ "$status" -eq 0 ]
        [ "$output" = "redhat" ]
    done
}

@test "os_pkg: detect_os_family via INSTALL_OS_ID arch variants" {
    for id in arch manjaro endeavouros artix steamos; do
        INSTALL_OS_ID="$id" INSTALL_OS_ID_LIKE=""
        run detect_os_family
        [ "$status" -eq 0 ]
        [ "$output" = "arch" ]
    done
}

@test "os_pkg: detect_os_family via ID_LIKE" {
    INSTALL_OS_ID="unknownos" INSTALL_OS_ID_LIKE="debian ubuntu"
    run detect_os_family
    [ "$output" = "debian" ]

    INSTALL_OS_ID="unknownos" INSTALL_OS_ID_LIKE="rhel fedora"
    run detect_os_family
    [ "$output" = "redhat" ]

    INSTALL_OS_ID="unknownos" INSTALL_OS_ID_LIKE="archlinux"
    run detect_os_family
    [ "$output" = "arch" ]
}

@test "os_pkg: resolve_pkg_names across families" {
    INSTALL_OS_ID=debian INSTALL_OS_ID_LIKE=""
    [ "$(resolve_pkg_names curl)" = "curl" ]
    [ "$(resolve_pkg_names whiptail)" = "whiptail" ]
    [ "$(resolve_pkg_names mail-transport)" = "msmtp mailutils" ]
    [ "$(resolve_pkg_names p7zip)" = "p7zip-full" ]
    [ "$(resolve_pkg_names rpi-eeprom)" = "rpi-eeprom" ]
    [ "$(resolve_pkg_names fwupd)" = "fwupd" ]
    [ "$(resolve_pkg_names nvme-cli)" = "nvme-cli" ]
    [ "$(resolve_pkg_names ssmtp)" = "ssmtp" ]

    INSTALL_OS_ID=fedora INSTALL_OS_ID_LIKE=""
    [ "$(resolve_pkg_names whiptail)" = "newt" ]
    [ "$(resolve_pkg_names mail-transport)" = "msmtp s-nail" ]
    [ "$(resolve_pkg_names p7zip)" = "7zip" ]
    [ "$(resolve_pkg_names ssmtp)" = "msmtp" ]
    [ "$(resolve_pkg_names rpi-eeprom)" = "" ]

    INSTALL_OS_ID=rocky INSTALL_OS_ID_LIKE=""
    [ "$(resolve_pkg_names p7zip)" = "p7zip" ]

    INSTALL_OS_ID=arch INSTALL_OS_ID_LIKE=""
    [ "$(resolve_pkg_names whiptail)" = "libnewt" ]
    [ "$(resolve_pkg_names mail-transport)" = "msmtp s-nail" ]
    [ "$(resolve_pkg_names p7zip)" = "p7zip" ]
}

@test "os_pkg: logical_is_installed and has_mail_sender" {
    run logical_is_installed curl
    [ "$status" -eq 0 ]
    run has_mail_sender
    [ "$status" -eq 0 ]
    run logical_is_installed mail-transport
    [ "$status" -eq 0 ]
}

@test "os_pkg: pkg_refresh and pkg_install_raw debian" {
    INSTALL_OS_ID=debian INSTALL_OS_ID_LIKE=""
    run pkg_refresh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "apt-get" || "$output" =~ "MOCK" || "$status" -eq 0 ]]

    run pkg_install_raw curl
    [ "$status" -eq 0 ]
}

@test "os_pkg: pkg_install skips installed logical deps" {
    INSTALL_OS_ID=debian INSTALL_OS_ID_LIKE=""
    run pkg_install curl
    [ "$status" -eq 0 ]
}

@test "os_pkg: pkg_install warns and continues on empty mapping" {
    INSTALL_OS_ID=fedora INSTALL_OS_ID_LIKE=""
    rm -f "$MOCK_DIR/rpi-eeprom-update"
    # Hide any host rpi-eeprom-update so the logical dep is treated as missing.
    run bash -c "export PATH=$MOCK_DIR:/usr/bin:/bin; source ./lib/os_pkg.sh; INSTALL_OS_ID=fedora INSTALL_OS_ID_LIKE=''; pkg_install rpi-eeprom"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no package mapping" || "$output" =~ "Warning" ]]
}

@test "os_pkg: pkg_update_system debian path" {
    INSTALL_OS_ID=debian INSTALL_OS_ID_LIKE=""
    run pkg_update_system
    [ "$status" -eq 0 ]
    [[ "$output" =~ "apt-get" || "$output" =~ "full-upgrade" || "$output" =~ "MOCK" ]]
}

@test "os_pkg: pkg_update_system redhat and arch paths" {
    cat << 'EOF' > "$MOCK_DIR/dnf"
#!/bin/bash
echo "[MOCK] dnf $*"
exit 0
EOF
    chmod +x "$MOCK_DIR/dnf"
    cat << 'EOF' > "$MOCK_DIR/pacman"
#!/bin/bash
echo "[MOCK] pacman $*"
exit 0
EOF
    chmod +x "$MOCK_DIR/pacman"

    INSTALL_OS_ID=fedora INSTALL_OS_ID_LIKE=""
    run pkg_update_system
    [ "$status" -eq 0 ]
    [[ "$output" =~ "dnf upgrade" || "$output" =~ "[MOCK] dnf" ]]

    INSTALL_OS_ID=arch INSTALL_OS_ID_LIKE=""
    run pkg_update_system
    [ "$status" -eq 0 ]
    [[ "$output" =~ "pacman -Syu" || "$output" =~ "[MOCK] pacman" ]]
}

@test "mail_send: mail_sender_cmd and send_mail" {
    run mail_sender_cmd
    [ "$status" -eq 0 ]
    [[ "$output" == "ssmtp" || "$output" == "msmtp" ]]

    body=$(mktemp)
    echo "hello body" > "$body"
    run send_mail "test@example.com" "Subj" "FromName" "$body"
    [ "$status" -eq 0 ]
    rm -f "$body"
}

@test "mail_send: write configs and read recipient" {
    export SSMTP_CONF="$MOCK_FS/etc/ssmtp/ssmtp.conf"
    export REVALIASES="$MOCK_FS/etc/ssmtp/revaliases"
    export MSMTP_CONF="$MOCK_FS/etc/msmtprc"
    mkdir -p "$(dirname "$SSMTP_CONF")" "$(dirname "$MSMTP_CONF")"
    # Ensure ssmtp-only read is not shadowed by a leftover msmtp default account (msmtp is preferred).
    rm -f "$MSMTP_CONF" "${MSMTP_CONF}.pre-migration"

    run write_mail_config_ssmtp "user@gmail.com" "secret"
    [ "$status" -eq 0 ]
    [ -f "$SSMTP_CONF" ]

    run mail_read_recipient_from_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"user@gmail.com"* ]]

    run write_mail_config_msmtp "user@gmail.com" "secret"
    [ "$status" -eq 0 ]
    [ -f "$MSMTP_CONF" ]

    run write_mail_config "user@gmail.com" "secret"
    [ "$status" -eq 0 ]
}


@test "sudo mock: preserves -n/-u/-g forms and rejects unsupported options" {
    local wrap args_file
    # Keep recorder under MOCK_DIR; use real chmod (PATH mock is a no-op).
    wrap="$MOCK_DIR/sudo_opt_probe"
    rm -rf "$wrap"
    mkdir -p "$wrap"
    args_file="$wrap/args.txt"
    # Rewrite mock sudo to invoke the recorder via bash (avoids exec-bit surprises).
    sed "s|/usr/bin/sudo|bash $wrap/real_sudo|g" "$MOCK_DIR/sudo" > "$wrap/sudo"
    cat << EOF > "$wrap/real_sudo"
#!/bin/bash
printf '%s\n' "\$@" > "$args_file"
EOF
    /usr/bin/chmod +x "$wrap/real_sudo"

    bash "$wrap/sudo" -n -H -u nobody -g nogroup /bin/true
    grep -qx -- '-n' "$args_file"
    grep -qx -- '-H' "$args_file"
    grep -qx -- '-u' "$args_file"
    grep -qx -- 'nobody' "$args_file"
    grep -qx -- '-g' "$args_file"
    grep -qx -- 'nogroup' "$args_file"

    bash "$wrap/sudo" -unobody -gnogroup /bin/true
    grep -qx -- '-u' "$args_file"
    grep -qx -- 'nobody' "$args_file"
    grep -qx -- '-g' "$args_file"
    grep -qx -- 'nogroup' "$args_file"

    run bash "$wrap/sudo" --bad /bin/true
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported option"* ]]

    run bash "$wrap/sudo" -u -n /bin/true
    [ "$status" -ne 0 ]
    [[ "$output" == *"-u requires a user"* ]]

    rm -rf "$wrap"
}
