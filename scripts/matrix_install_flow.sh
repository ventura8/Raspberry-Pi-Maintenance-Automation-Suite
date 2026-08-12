#!/usr/bin/env bash
# Shared text-UI fresh install / uninstall helpers for distro matrix lanes.
# shellcheck shell=bash

matrix_cleanup_mail_conf() {
    rm -f "${SSMTP_CONF:-}" "${REVALIASES:-}" "${MSMTP_CONF:-}" 2> /dev/null || true
}

matrix_prepare_install_env() {
    export TEST_MODE="${TEST_MODE:-true}"
    export INSTALL_FORCE_TEXT_UI=1
    export INSTALL_DIR="${INSTALL_DIR:?INSTALL_DIR must be set}"

    if [ "${MATRIX_ALLOW_RM_INSTALL_DIR:-0}" != "1" ]; then
        echo "ERROR: MATRIX_ALLOW_RM_INSTALL_DIR=1 required before removing INSTALL_DIR" >&2
        return 1
    fi
    case "$INSTALL_DIR" in
        /tmp/pi-scripts*) ;;
        *)
            echo "ERROR: INSTALL_DIR must be under /tmp/pi-scripts* (got: $INSTALL_DIR)" >&2
            return 1
            ;;
    esac

    # Always use fresh conf paths — write_mail_config may leave root-only files behind.
    export SSMTP_CONF="/tmp/matrix-ssmtp-${RANDOM}-$$.conf"
    export REVALIASES="/tmp/matrix-revaliases-${RANDOM}-$$"
    export MSMTP_CONF="/tmp/matrix-msmtprc-${RANDOM}-$$"
    : > "$SSMTP_CONF"
    : > "$REVALIASES"
    : > "$MSMTP_CONF"
    chmod 600 "$SSMTP_CONF" "$REVALIASES" "$MSMTP_CONF"
    rm -rf "$INSTALL_DIR"
}

# Deterministic non-interactive fresh install (INSTALL_MATRIX_FRESH contract).
matrix_run_text_fresh_install() {
    local email="${1:-matrix@example.com}"
    local pass="${2:-app-password-test}"
    local rc=0

    export INSTALL_MATRIX_FRESH=1
    export MATRIX_EMAIL="$email"
    export MATRIX_PASS="$pass"
    export INSTALL_FORCE_TEXT_UI=1
    export TEST_MODE="${TEST_MODE:-true}"

    bash ./install.sh || rc=$?
    unset INSTALL_MATRIX_FRESH MATRIX_EMAIL MATRIX_PASS
    return "$rc"
}

matrix_assert_installed() {
    local expected actual
    [ -d "$INSTALL_DIR" ] || {
        echo "ERROR: INSTALL_DIR missing: $INSTALL_DIR" >&2
        return 1
    }
    [ -f "$INSTALL_DIR/update_pi_os.sh" ] || {
        echo "ERROR: update_pi_os.sh missing after install" >&2
        return 1
    }
    [ -f "$INSTALL_DIR/update_self.sh" ] || {
        echo "ERROR: update_self.sh missing after install" >&2
        return 1
    }
    [ -f "$INSTALL_DIR/lib/os_pkg.sh" ] || {
        echo "ERROR: lib/os_pkg.sh missing after install" >&2
        return 1
    }
    [ -f "$INSTALL_DIR/lib/mail_send.sh" ] || {
        echo "ERROR: lib/mail_send.sh missing after install" >&2
        return 1
    }
    [ -f "$INSTALL_DIR/.version" ] || {
        echo "ERROR: .version missing after install" >&2
        return 1
    }
    if [ -f ./VERSION ]; then
        expected=$(tr -d '[:space:]' < ./VERSION)
        actual=$(tr -d '[:space:]' < "$INSTALL_DIR/.version")
        if [ "$expected" != "$actual" ]; then
            echo "ERROR: .version ($actual) does not match VERSION ($expected)" >&2
            return 1
        fi
    fi
}

matrix_run_uninstall() {
    if ! bash ./uninstall.sh; then
        echo "ERROR: uninstall.sh failed" >&2
        matrix_cleanup_mail_conf
        return 1
    fi
    if [ -d "$INSTALL_DIR" ]; then
        echo "ERROR: INSTALL_DIR still present after uninstall: $INSTALL_DIR" >&2
        matrix_cleanup_mail_conf
        return 1
    fi
    matrix_cleanup_mail_conf
}
