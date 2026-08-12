#!/usr/bin/env bash
# Shared helpers for test image builds.
set -euo pipefail

create_ci_user() {
    local user="${1:-pi}"
    local uid="${2:-${CI_UID:-1000}}"
    local gid="${3:-${CI_GID:-1000}}"
    local taken=""

    # Prefer numeric -g/-u so reclaiming a distro default account (e.g. ubuntu:1000)
    # cannot leave us referencing a deleted group name.
    if ! getent group "$gid" > /dev/null 2>&1; then
        groupadd -g "$gid" "$user"
    fi

    if id "$user" > /dev/null 2>&1; then
        usermod -u "$uid" -g "$gid" "$user"
    else
        if getent passwd "$uid" > /dev/null 2>&1; then
            taken="$(getent passwd "$uid" | cut -d: -f1)"
            userdel -r "$taken" 2> /dev/null || userdel "$taken" 2> /dev/null || true
            if ! getent group "$gid" > /dev/null 2>&1; then
                groupadd -g "$gid" "$user"
            fi
        fi
        useradd -m -u "$uid" -g "$gid" -s /bin/bash "$user"
    fi

    echo "$user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$user"
    chmod 440 "/etc/sudoers.d/$user"

    # Fail the image build early if UID/GID binding did not stick.
    test "$(id -u "$user")" = "$uid"
    test "$(id -g "$user")" = "$gid"
}

prepare_mail_dirs() {
    mkdir -p /etc/ssmtp
    touch /etc/ssmtp/ssmtp.conf /etc/ssmtp/revaliases
    chmod 666 /etc/ssmtp/ssmtp.conf /etc/ssmtp/revaliases
    touch /etc/msmtprc
    chmod 666 /etc/msmtprc
}

install_kcov_from_source() {
    local version="${1:-v43}"
    git clone --depth 1 --branch "$version" https://github.com/SimonKagstrom/kcov.git /tmp/kcov
    cmake -S /tmp/kcov -B /tmp/kcov/build
    cmake --build /tmp/kcov/build
    cmake --install /tmp/kcov/build
    rm -rf /tmp/kcov
}
