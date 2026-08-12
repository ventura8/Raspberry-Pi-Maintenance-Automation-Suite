#!/usr/bin/env bash
# Mail sending helpers: prefer ssmtp, fall back to msmtp.
# shellcheck shell=bash

# Soft gettext stubs when lib/i18n.sh is not sourced yet.
_I18N_SOFT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/i18n_soft.sh"
if [ -f "$_I18N_SOFT" ]; then
    # shellcheck source=lib/i18n_soft.sh
    source "$_I18N_SOFT"
elif ! declare -F _pi_gettext > /dev/null 2>&1; then
    _pi_gettext() { printf '%s' "$1"; }
    _pi_gettextf() {
        local format="$1" argument prefix suffix
        shift
        for argument in "$@"; do
            case "$format" in
                *%s*)
                    prefix=${format%%\%s*}
                    suffix=${format#*%s}
                    format="${prefix}${argument}${suffix}"
                    ;;
            esac
        done
        printf '%s' "$format"
    }
    _pi_echo() { printf '%s\n' "$1"; }
    _pi_echof() {
        local format
        format=$(_pi_gettextf "$@")
        printf '%s\n' "$format"
    }
fi
unset _I18N_SOFT

SSMTP_CONF="${SSMTP_CONF:-/etc/ssmtp/ssmtp.conf}"
REVALIASES="${REVALIASES:-/etc/ssmtp/revaliases}"
MSMTP_CONF="${MSMTP_CONF:-/etc/msmtprc}"

mail_sender_cmd() {
    if command -v ssmtp > /dev/null 2>&1; then
        echo "ssmtp"
        return 0
    fi
    if command -v msmtp > /dev/null 2>&1; then
        echo "msmtp"
        return 0
    fi
    return 1
}

mail_read_recipient_from_config() {
    local recipient=""
    if [ -f "$SSMTP_CONF" ]; then
        recipient=$(grep "^root=" "$SSMTP_CONF" 2> /dev/null | cut -d= -f2)
        [ -n "$recipient" ] && {
            echo "$recipient"
            return 0
        }
        recipient=$(grep "^AuthUser=" "$SSMTP_CONF" 2> /dev/null | cut -d= -f2)
        [ -n "$recipient" ] && {
            echo "$recipient"
            return 0
        }
    fi
    if [ -f "$MSMTP_CONF" ]; then
        recipient=$(grep -E '^user\s+' "$MSMTP_CONF" 2> /dev/null | awk '{print $2}' | head -n 1)
        [ -n "$recipient" ] && {
            echo "$recipient"
            return 0
        }
    fi
    return 1
}

# send_mail <to> <subject> <from_name> <body_file_or_->
# If body is "-", read body from stdin after headers are composed from remaining stdin not used —
# prefer body file path. For stdin body, pass a temp file.
send_mail() {
    local to="$1" subject="$2" from_name="$3" body_src="${4:--}"
    local sender body
    sender=$(mail_sender_cmd) || {
        _pi_echo "No mail sender (ssmtp/msmtp) found, skipping email notification."
        return 1
    }

    if [ "$body_src" = "-" ]; then
        body=$(cat)
    else
        body=$(cat "$body_src")
    fi

    if [ "$sender" = "ssmtp" ]; then
        ssmtp "$to" << EOF
To: $to
Subject: $subject
From: "$from_name" <$to>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$body
EOF
        return $?
    fi

    # msmtp
    msmtp --account=default -t << EOF
To: $to
Subject: $subject
From: "$from_name" <$to>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$body
EOF
}

write_mail_config_ssmtp() {
    local email="$1" password="$2" hub="${3:-smtp.gmail.com:587}"
    sudo mkdir -p "$(dirname "$SSMTP_CONF")"
    # Pre-create with restrictive mode before writing secrets (TOCTOU). Prefer touch+chmod so
    # test mocks that intercept tee still own the file.
    sudo touch "$SSMTP_CONF"
    sudo chmod 600 "$SSMTP_CONF"
    cat << EOF | sudo tee "$SSMTP_CONF" > /dev/null
root=$email
mailhub=$hub
AuthUser=$email
AuthPass=$password
UseSTARTTLS=YES
FromLineOverride=YES
EOF
    sudo chown root:mail "$SSMTP_CONF" 2> /dev/null || sudo chown root:root "$SSMTP_CONF"
    sudo chmod 640 "$SSMTP_CONF"
    sudo touch "$REVALIASES"
    sudo chmod 600 "$REVALIASES"
    echo "root:$email:$hub" | sudo tee "$REVALIASES" > /dev/null
    sudo chmod 640 "$REVALIASES"
}

write_mail_config_msmtp() {
    local email="$1" password="$2" host="${3:-smtp.gmail.com}" port="${4:-587}"
    sudo mkdir -p "$(dirname "$MSMTP_CONF")"
    sudo touch "$MSMTP_CONF"
    sudo chmod 600 "$MSMTP_CONF"
    cat << EOF | sudo tee "$MSMTP_CONF" > /dev/null
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           $host
port           $port
from           $email
user           $email
password       $password
EOF
    sudo chmod 600 "$MSMTP_CONF"
}

# Write mailer config for the active OS family / available mailer.
write_mail_config() {
    local email="$1" password="$2"
    if command -v ssmtp > /dev/null 2>&1 || [ "$(detect_os_family 2> /dev/null || echo debian)" = "debian" ]; then
        if command -v ssmtp > /dev/null 2>&1 || ! command -v msmtp > /dev/null 2>&1; then
            write_mail_config_ssmtp "$email" "$password"
            return $?
        fi
    fi
    write_mail_config_msmtp "$email" "$password"
}
