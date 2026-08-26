#!/usr/bin/env bash
# Mail sending helpers: prefer msmtp (verifies TLS certs), fall back to ssmtp.
# shellcheck shell=bash

_UI_MSG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui_msg.sh"
if [ -f "$_UI_MSG" ]; then
    # shellcheck source=lib/ui_msg.sh
    source "$_UI_MSG"
elif ! declare -F _pi_echo > /dev/null 2>&1; then
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
unset _UI_MSG

SSMTP_CONF="${SSMTP_CONF:-/etc/ssmtp/ssmtp.conf}"
REVALIASES="${REVALIASES:-/etc/ssmtp/revaliases}"
MSMTP_CONF="${MSMTP_CONF:-/etc/msmtprc}"

# Resolve field $1 (e.g. "user", "host") for msmtp's "default" account from config text on
# stdin, per msmtp's own inheritance rules: an account's own setting wins; otherwise its parents
# are checked (`account NAME : PARENT…` or attached `account NAME: PARENT…`, later entries
# overriding earlier ones, each parent's own chain walked recursively); if nothing in the chain
# defines the field, fall back to the top-level "defaults" block — but only when a usable
# "default" account exists, either an explicit `account default` or msmtp's implicit
# compatibility form (bare directives with no preceding `defaults`/`account` keyword at all;
# `msmtp --account=default` accepts either). A bare `defaults` block alone is not usable.
# Prints nothing and fails if unresolved.
_msmtp_resolve_default_field() {
    awk -v field="$1" '
        # msmtp requires every inherited account to already be declared (parsed earlier in the
        # file) — an undeclared or forward-referenced parent makes the whole config invalid, not
        # just that one lookup. bound is the referencing accounts declaration order; a parent
        # must exist and have been declared strictly before it.
        function resolve(name, bound,    i, cnt, plist, parts, result) {
            if (visited[name]) return ""
            visited[name] = 1
            if (val[name] != "") return val[name]
            plist = parentof[name]
            if (plist == "") {
                if (snapshot[name] != "") return snapshot[name]
                return ""
            }
            # msmtp: account name [: account[,...]] — parents are comma-separated only
            # (conf.c read_account_list). Trim each token; do not split on bare spaces.
            cnt = split(plist, parts, ",")
            for (i = cnt; i >= 1; i--) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                if (parts[i] == "") continue
                if (!(parts[i] in accounts) || orderof[parts[i]] >= bound) {
                    invalid = 1
                    return ""
                }
                result = resolve(parts[i], orderof[parts[i]])
                if (result != "") return result
            }
            if (snapshot[name] != "") return snapshot[name]
            return ""
        }
        /^defaults[[:space:]]*$/ { cur = "__defaults__"; next }
        # msmtp compatibility form: directives with no preceding "defaults"/"account" keyword at
        # all form an implicit account named "default" (conf.c) — distinct from a bare "defaults"
        # block alone, which is NOT a usable account. Falls through so the field-capture rule
        # below still applies to this same line.
        cur == "" && NF > 0 && $1 !~ /^#/ && !/^defaults[[:space:]]*$/ && !/^account[[:space:]]+/ {
            name = "default"
            accounts[name] = 1
            parentof[name] = ""
            orderof[name] = ++seq
            snapshot[name] = val["__defaults__"]
            cur = name
        }
        /^account[[:space:]]+/ {
            rest = $0
            sub(/^account[[:space:]]+/, "", rest)
            if (match(rest, /:/)) {
                name = substr(rest, 1, RSTART - 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
                plist = substr(rest, RSTART + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", plist)
                parentof[name] = plist
            } else {
                split(rest, parts, /[[:space:]]+/)
                name = parts[1]
                parentof[name] = ""
            }
            accounts[name] = 1
            orderof[name] = ++seq
            # Snapshot defaults at account start (msmtp does not inherit later defaults blocks).
            snapshot[name] = val["__defaults__"]
            cur = name
            next
        }
        cur != "" && $1 == field && NF >= 2 { val[cur] = $2 }
        END {
            if (!("default" in accounts)) exit 1
            r = resolve("default", orderof["default"])
            if (invalid) exit 1
            if (r != "") { print r; exit 0 }
            exit 1
        }
    '
}

# Resolve field $1 from MSMTP_CONF, falling back to non-interactive `sudo -n cat` when the file
# isn't directly readable (e.g. mode 640 root:mail and the caller isn't in the mail group yet —
# group membership added by `usermod -aG mail` doesn't apply to an already-running process/session).
# Every direct MSMTP_CONF reader in this file (mail_read_recipient_from_config,
# _msmtp_has_default_account, migrate's own usability check) goes through this so none of them
# silently miss a real, working account just because of a read-permission gap. install.sh's own
# callers pipe their own `sudo cat` through _msmtp_resolve_default_field directly instead, since
# they may need install.sh's own sudo semantics (interactive install vs. cron).
_msmtp_default_field() {
    [ -f "$MSMTP_CONF" ] || return 1
    local result
    result=$(_msmtp_resolve_default_field "$1" < "$MSMTP_CONF") && [ -n "$result" ] && {
        printf '%s' "$result"
        return 0
    }
    command -v sudo > /dev/null 2>&1 || return 1
    local content
    content=$(sudo -n cat "$MSMTP_CONF" 2> /dev/null) || return 1
    [ -n "$content" ] || return 1
    printf '%s' "$content" | _msmtp_resolve_default_field "$1"
}

# True if MSMTP_CONF defines a usable "default" account (after inheritance) for
# `msmtp --account=default`.
_msmtp_has_default_account() {
    _msmtp_default_field host > /dev/null 2>&1
}

mail_sender_cmd() {
    if command -v msmtp > /dev/null 2>&1 && _msmtp_has_default_account; then
        echo "msmtp"
        return 0
    fi
    if command -v ssmtp > /dev/null 2>&1; then
        echo "ssmtp"
        return 0
    fi
    # No usable ssmtp fallback: still try msmtp (its own error is clearer than declaring no
    # sender at all) rather than failing when the msmtp binary is the only thing installed.
    if command -v msmtp > /dev/null 2>&1; then
        echo "msmtp"
        return 0
    fi
    return 1
}

mail_read_recipient_from_config() {
    local recipient=""
    # Prefer msmtp: after migration the legacy ssmtp file is intentionally left in place, so
    # reading ssmtp first would report a stale address while send_mail uses the msmtp account.
    recipient=$(_msmtp_default_field user 2> /dev/null)
    [ -n "$recipient" ] && {
        echo "$recipient"
        return 0
    }
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
    return 1
}

# Best-effort, silent: if a legacy ssmtp config carries live credentials and msmtp is already
# installed (by the install/explicit-configuration path) but not yet configured, reconfigure it
# with the same credentials so upgraded installs move off the non-cert-verifying ssmtp path with
# no user action. Never installs packages or prompts — only rewrites a config file — so it never
# stalls send_mail. Any error here leaves the existing ssmtp config untouched (migration does not
# rewrite ssmtp.conf; TLS_CA_File hardening only applies to configs written fresh by this suite).
migrate_mail_config_to_msmtp() {
    [ -f "$SSMTP_CONF" ] || return 0
    # Only skip migration when MSMTP_CONF already defines a usable "default" account (what
    # send_mail's `msmtp --account=default` needs) — an empty or partial file (e.g. a
    # pre-created/touched placeholder) must not block migrating good ssmtp credentials.
    _msmtp_has_default_account && return 0
    command -v msmtp > /dev/null 2>&1 || return 0

    local email password hub host port usestarttls usetls starttls tls conf_text=""
    email=$(grep "^AuthUser=" "$SSMTP_CONF" 2> /dev/null | cut -d= -f2)
    password=$(grep "^AuthPass=" "$SSMTP_CONF" 2> /dev/null | cut -d= -f2-)
    # ssmtp.conf is often mode 640 root:mail — non-root/cron may need a passwordless sudo read.
    if { [ -z "$email" ] || [ -z "$password" ]; } && command -v sudo > /dev/null 2>&1; then
        conf_text=$(sudo -n cat "$SSMTP_CONF" 2> /dev/null) || conf_text=""
        if [ -n "$conf_text" ]; then
            [ -n "$email" ] || email=$(printf '%s\n' "$conf_text" | grep "^AuthUser=" | cut -d= -f2)
            [ -n "$password" ] || password=$(printf '%s\n' "$conf_text" | grep "^AuthPass=" | cut -d= -f2-)
        fi
    fi
    [ -n "$email" ] && [ -n "$password" ] || return 0
    # write_mail_config_msmtp needs elevated writes; never prompt for a sudo password from cron.
    if [ "$(id -u)" -ne 0 ]; then
        command -v sudo > /dev/null 2>&1 || return 0
        sudo -n true 2> /dev/null || return 0
    fi
    # Preserve any pre-existing msmtp configuration before it is replaced (e.g. named-account-only
    # files that fail _msmtp_has_default_account). One-time backup; never overwrite an existing one.
    # Root hosts may lack sudo in PATH (minimal containers); use plain cp there. If the backup
    # cannot be created, abort without writing MSMTP_CONF so a hand-written config is not lost.
    # A backup already existing means a prior migration already used its one shot here — proceeding
    # would silently overwrite MSMTP_CONF's current (unbacked-up) content with no way to recover it,
    # so abort instead of replacing it further.
    if [ -s "$MSMTP_CONF" ]; then
        [ -e "${MSMTP_CONF}.pre-migration" ] && return 0
        if [ "$(id -u)" -eq 0 ]; then
            cp -p "$MSMTP_CONF" "${MSMTP_CONF}.pre-migration" 2> /dev/null || return 0
        else
            sudo -n cp -p "$MSMTP_CONF" "${MSMTP_CONF}.pre-migration" 2> /dev/null || return 0
        fi
    fi
    if [ -n "$conf_text" ]; then
        hub=$(printf '%s\n' "$conf_text" | grep "^mailhub=" | cut -d= -f2)
        usestarttls=$(printf '%s\n' "$conf_text" | grep "^UseSTARTTLS=" | cut -d= -f2)
        usetls=$(printf '%s\n' "$conf_text" | grep "^UseTLS=" | cut -d= -f2)
    else
        hub=$(grep "^mailhub=" "$SSMTP_CONF" 2> /dev/null | cut -d= -f2)
        usestarttls=$(grep "^UseSTARTTLS=" "$SSMTP_CONF" 2> /dev/null | cut -d= -f2)
        usetls=$(grep "^UseTLS=" "$SSMTP_CONF" 2> /dev/null | cut -d= -f2)
    fi
    host="${hub%%:*}"
    port="${hub##*:}"
    # ssmtp mailhub is host[:port]; a bare host is valid and defaults to port 25.
    if [ -n "$hub" ] && [ "$host" = "$port" ]; then
        port=25
    fi
    local usestarttls_lc usetls_lc
    # ssmtp defaults both UseTLS and UseSTARTTLS to NO when absent from ssmtp.conf, so a legacy
    # config with neither line set is plaintext — default off and only enable on an explicit YES,
    # not the other way around (defaulting to "on" would silently upgrade a working plaintext
    # config into TLS/STARTTLS and break delivery).
    tls="off"
    starttls="off"
    usestarttls_lc=$(printf '%s' "$usestarttls" | tr '[:upper:]' '[:lower:]')
    usetls_lc=$(printf '%s' "$usetls" | tr '[:upper:]' '[:lower:]')
    if [ "$usetls_lc" = "yes" ]; then
        tls="on"
    fi
    if [ "$usestarttls_lc" = "yes" ]; then
        tls="on"
        starttls="on"
    fi
    # Port 465 is implicit TLS (SMTPS), not STARTTLS: TLS is active from connect.
    if [ "$port" = "465" ]; then
        tls="on"
        starttls="off"
    fi
    if [ -n "$host" ] && [[ "$port" =~ ^[0-9]+$ ]] &&
        [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        write_mail_config_msmtp "$email" "$password" "$host" "$port" "$starttls" "$tls"
    else
        # mailhub was missing/malformed (empty host, or a non-numeric/out-of-range port): fall
        # back to Gmail's STARTTLS default (587), not an invalid port, and not whatever STARTTLS
        # mode was parsed for the discarded host/port.
        write_mail_config_msmtp "$email" "$password" "smtp.gmail.com" "587" "on" "on"
    fi
}

# send_mail <to> <subject> <from_name> <body_file_or_->
# If body is "-", read body from stdin after headers are composed from remaining stdin not used —
# prefer body file path. For stdin body, pass a temp file.
send_mail() {
    local to="$1" subject="$2" from_name="$3" body_src="${4:--}"
    local sender body
    migrate_mail_config_to_msmtp 2> /dev/null || true
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

    # msmtp: system conf is often mode 640 root:mail. User-crontab senders (e.g. update_pi_apps)
    # cannot read it directly; elevate with sudo -n to match _msmtp_has_default_account detection.
    local -a msmtp_cmd=(msmtp)
    if [ ! -r "$MSMTP_CONF" ] && [ "$(id -u)" -ne 0 ]; then
        command -v sudo > /dev/null 2>&1 || return 1
        sudo -n true 2> /dev/null || return 1
        msmtp_cmd=(sudo -n msmtp)
    fi
    "${msmtp_cmd[@]}" --account=default -t << EOF
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
    local ca_bundle
    ca_bundle=$(_mail_tls_ca_bundle)
    # TLS_CA_File is written best-effort for ssmtp builds/forks that recognize it, but it is NOT
    # a verified fix: Debian/Ubuntu's packaged ssmtp (2.65) does not recognize TLS_CA_File (or any
    # "AllowSelfSigned"-style toggle) at all — the binary calls no SSL_CTX_set_verify /
    # SSL_get_verify_result and performs zero certificate validation regardless of this file's
    # contents. There is no ssmtp.conf setting that fixes this on that build. ssmtp is a fallback
    # of last resort only; msmtp is the only mailer this suite treats as capable of verified TLS.
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
UseTLS=YES
TLS_CA_File=$ca_bundle
FromLineOverride=YES
EOF
    sudo chown root:mail "$SSMTP_CONF" 2> /dev/null || sudo chown root:root "$SSMTP_CONF"
    sudo chmod 640 "$SSMTP_CONF"
    sudo touch "$REVALIASES"
    sudo chmod 600 "$REVALIASES"
    echo "root:$email:$hub" | sudo tee "$REVALIASES" > /dev/null
    sudo chmod 640 "$REVALIASES"
}

# Resolve a readable CA bundle for the active OS family. Debian/Ubuntu/Arch ship
# /etc/ssl/certs/ca-certificates.crt; RHEL/Fedora/Rocky ship /etc/pki/tls/certs/ca-bundle.crt.
_mail_tls_ca_bundle() {
    local family=""
    if declare -F detect_os_family > /dev/null 2>&1; then
        family=$(detect_os_family 2> /dev/null) || family=""
    fi
    if [ "$family" = "redhat" ] && [ -r /etc/pki/tls/certs/ca-bundle.crt ]; then
        echo /etc/pki/tls/certs/ca-bundle.crt
        return 0
    fi
    if [ -r /etc/ssl/certs/ca-certificates.crt ]; then
        echo /etc/ssl/certs/ca-certificates.crt
        return 0
    fi
    if [ -r /etc/pki/tls/certs/ca-bundle.crt ]; then
        echo /etc/pki/tls/certs/ca-bundle.crt
        return 0
    fi
    echo /etc/ssl/certs/ca-certificates.crt
}

write_mail_config_msmtp() {
    local email="$1" password="$2" host="${3:-smtp.gmail.com}" port="${4:-587}" starttls="${5:-on}" tls="${6:-on}"
    local ca_bundle
    ca_bundle=$(_mail_tls_ca_bundle)
    sudo mkdir -p "$(dirname "$MSMTP_CONF")"
    sudo touch "$MSMTP_CONF"
    sudo chmod 600 "$MSMTP_CONF"
    cat << EOF | sudo tee "$MSMTP_CONF" > /dev/null
defaults
auth           on
tls            $tls
tls_starttls   $starttls
tls_trust_file $ca_bundle
syslog         LOG_MAIL

account        default
host           $host
port           $port
from           $email
user           $email
password       $password
EOF
    sudo chown root:mail "$MSMTP_CONF" 2> /dev/null || sudo chown root:root "$MSMTP_CONF"
    sudo chmod 640 "$MSMTP_CONF"
}

# Write mailer config for the active OS family. msmtp is preferred everywhere (it verifies the
# SMTP server's TLS certificate); ssmtp is only used as a last resort when msmtp can't be installed.
write_mail_config() {
    local email="$1" password="$2"
    if ! command -v msmtp > /dev/null 2>&1 && declare -F pkg_install > /dev/null 2>&1; then
        pkg_install msmtp > /dev/null 2>&1
    fi
    if command -v msmtp > /dev/null 2>&1; then
        write_mail_config_msmtp "$email" "$password"
        return $?
    fi
    write_mail_config_ssmtp "$email" "$password"
}
