#!/usr/bin/env bats
# E2E ssmtp -> msmtp migration coverage against REAL msmtp/ssmtp binaries (REAL_DEPS=1 distro
# matrix lanes only). Unlike the unit-level bats suites (which mock both binaries and only grep
# the generated config), every test here re-validates the migrated /generated msmtp config by
# actually invoking the real `msmtp --account=default -P` (pretend/no-network parse) against it,
# so a regression that produces a config real msmtp rejects fails here even if our own
# grep/awk-based resolver still "agrees" with itself.
#
# ssmtp is only packaged on Debian-family systems (see lib/os_pkg.sh); on Fedora/RHEL/Rocky/Arch
# the "ssmtp" logical dependency resolves to msmtp instead, so there is no real ssmtp binary to
# migrate from. Every test skips gracefully when either real binary is missing.

setup() {
    export TEST_MODE=true
    export REAL_DEPS=1
    command -v msmtp > /dev/null 2>&1 || skip "real msmtp binary not installed on this image"
    command -v ssmtp > /dev/null 2>&1 || skip "real ssmtp binary not packaged on this OS family"

    # shellcheck source=../../lib/os_pkg.sh
    source ./lib/os_pkg.sh
    # shellcheck source=../../lib/mail_send.sh
    source ./lib/mail_send.sh

    export SSMTP_CONF="/tmp/e2e-migrate-ssmtp-${BATS_TEST_NUMBER}-$$.conf"
    export REVALIASES="/tmp/e2e-migrate-revaliases-${BATS_TEST_NUMBER}-$$"
    export MSMTP_CONF="/tmp/e2e-migrate-msmtprc-${BATS_TEST_NUMBER}-$$"
    # write_mail_config_msmtp chowns MSMTP_CONF to root:mail, so any leftover from a prior run at
    # this same (test-number-based) path needs sudo to remove.
    sudo -n rm -f "$SSMTP_CONF" "$REVALIASES" "$MSMTP_CONF" "${MSMTP_CONF}.pre-migration" 2> /dev/null || true
}

teardown() {
    sudo -n rm -f "$SSMTP_CONF" "$REVALIASES" "$MSMTP_CONF" "${MSMTP_CONF}.pre-migration" 2> /dev/null || true
}

# Write to MSMTP_CONF as root:mail 640, matching what a real pre-existing config (whether written
# by write_mail_config_msmtp previously, or hand-created per the README's documented permissions)
# actually looks like in production — not a user-owned file, which real deployments never have.
write_msmtp_conf_direct() {
    printf '%s\n' "$1" | sudo -n tee "$MSMTP_CONF" > /dev/null
    sudo -n chown root:mail "$MSMTP_CONF" 2> /dev/null || sudo -n chown root:root "$MSMTP_CONF"
    sudo -n chmod 640 "$MSMTP_CONF"
}

# Ground-truth check: ask the REAL msmtp binary to parse+resolve the default account (no network).
# Generated configs are root:mail 640 (matching production); the test user isn't necessarily a
# "mail" group member the way the installer-provisioned e2e user is, so read via sudo like root
# cron jobs would rather than re-testing group-membership plumbing here.
real_msmtp_default_ok() {
    sudo -n msmtp --file="$MSMTP_CONF" --account=default -P > /dev/null 2>&1
}

real_msmtp_field() {
    sudo -n msmtp --file="$MSMTP_CONF" --account=default -P 2> /dev/null | awk -v f="$1" '$1==f {print $3}'
}

write_ssmtp_conf() {
    printf '%s\n' "$@" > "$SSMTP_CONF"
    chmod 600 "$SSMTP_CONF"
}

# Root:mail 640, matching production ssmtp.conf permissions — the invoking test user cannot read
# AuthUser/AuthPass directly, forcing migrate_mail_config_to_msmtp's `sudo -n cat` fallback path.
write_ssmtp_conf_root_owned() {
    printf '%s\n' "$@" | sudo -n tee "$SSMTP_CONF" > /dev/null
    sudo -n chown root:mail "$SSMTP_CONF" 2> /dev/null || sudo -n chown root:root "$SSMTP_CONF"
    sudo -n chmod 640 "$SSMTP_CONF"
}

# Run "$@" with binary $1 made unresolvable via PATH, while every other tool the migration code
# needs stays available — proves the "binary not installed" guards actually take that branch,
# not just that they'd theoretically compile.
run_without_binary() {
    local hidden="$1"
    shift
    local shadow tool real
    shadow=$(mktemp -d)
    for tool in grep cut tr sudo cp cat awk dirname mkdir touch chmod chown tee id sed head \
        true false env bash sh msmtp ssmtp; do
        [ "$tool" = "$hidden" ] && continue
        real=$(command -v "$tool" 2> /dev/null) || continue
        ln -sf "$real" "$shadow/$tool"
    done
    PATH="$shadow" "$@"
    local rc=$?
    rm -rf "$shadow"
    return $rc
}

# Run "$@" with a fake `sudo` that denies passwordless elevation (`sudo -n ...` fails, as it
# would on a host without NOPASSWD configured for this user) while every other tool stays real.
run_without_passwordless_sudo() {
    local shadow tool real
    shadow=$(mktemp -d)
    cat << 'FAKESUDO' > "$shadow/sudo"
#!/bin/bash
for arg in "$@"; do
    [ "$arg" = "-n" ] && { echo "sudo: a password is required" >&2; exit 1; }
done
exec /usr/bin/sudo "$@"
FAKESUDO
    chmod +x "$shadow/sudo"
    for tool in grep cut tr cp cat awk dirname mkdir touch chmod chown tee id sed head \
        true false env bash sh msmtp ssmtp; do
        real=$(command -v "$tool" 2> /dev/null) || continue
        ln -sf "$real" "$shadow/$tool"
    done
    PATH="$shadow" "$@"
    local rc=$?
    rm -rf "$shadow"
    return $rc
}

@test "e2e migration: STARTTLS port-587 ssmtp config migrates to a real msmtp-valid default account" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]
    [ -f "$MSMTP_CONF" ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field host)" = "smtp.gmail.com" ]
    [ "$(real_msmtp_field port)" = "587" ]
    [ "$(real_msmtp_field user)" = "user@gmail.com" ]
    [ "$(real_msmtp_field tls_starttls)" = "on" ]
}

@test "e2e migration: implicit-TLS port-465 ssmtp config migrates with STARTTLS off, TLS on" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:465" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseTLS=YES"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field port)" = "465" ]
    [ "$(real_msmtp_field tls)" = "on" ]
    [ "$(real_msmtp_field tls_starttls)" = "off" ]
}

@test "e2e migration: plaintext ssmtp config (no UseTLS/UseSTARTTLS lines) stays plaintext" {
    # ssmtp's own default for both is NO when the lines are absent entirely.
    write_ssmtp_conf \
        "root=user@example.com" \
        "mailhub=smtp.internal.example:25" \
        "AuthUser=user@example.com" \
        "AuthPass=secret"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field tls)" = "off" ]
    [ "$(real_msmtp_field tls_starttls)" = "off" ]
}

@test "e2e migration: explicit UseSTARTTLS=NO / UseTLS=NO stays plaintext" {
    write_ssmtp_conf \
        "root=user@example.com" \
        "mailhub=smtp.internal.example" \
        "AuthUser=user@example.com" \
        "AuthPass=secret" \
        "UseTLS=NO" \
        "UseSTARTTLS=NO"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field tls)" = "off" ]
    [ "$(real_msmtp_field tls_starttls)" = "off" ]
    # Bare ssmtp mailhub host (no :port) defaults to port 25.
    [ "$(real_msmtp_field port)" = "25" ]
}

@test "e2e migration: malformed mailhub falls back to a real-msmtp-valid Gmail default" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"
    # No mailhub line at all.

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field host)" = "smtp.gmail.com" ]
    [ "$(real_msmtp_field port)" = "587" ]
    [ "$(real_msmtp_field tls_starttls)" = "on" ]
}

@test "e2e migration: non-numeric / out-of-range port falls back to a real-msmtp-valid Gmail default" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.example.com:notaport" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field host)" = "smtp.gmail.com" ]
    [ "$(real_msmtp_field port)" = "587" ]
}

@test "e2e migration: skipped entirely once MSMTP_CONF already has a real-msmtp-valid default account" {
    write_ssmtp_conf \
        "root=stale@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=stale@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"

    run write_mail_config_msmtp "already@gmail.com" "secret"
    [ "$status" -eq 0 ]
    run real_msmtp_default_ok
    [ "$status" -eq 0 ]

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    # Untouched: still the pre-existing account, not the stale ssmtp credentials.
    [ "$(real_msmtp_field user)" = "already@gmail.com" ]
    [ ! -e "${MSMTP_CONF}.pre-migration" ]
}

@test "e2e migration: proceeds and backs up when MSMTP_CONF exists but has no usable account" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"
    write_msmtp_conf_direct $'account other\nuser leftover@example.com'

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    [ -f "${MSMTP_CONF}.pre-migration" ]
    run sudo -n grep -q "leftover@example.com" "${MSMTP_CONF}.pre-migration"
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field user)" = "user@gmail.com" ]
}

@test "e2e migration: a second migration attempt aborts once a backup already exists" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"
    write_msmtp_conf_direct $'account other\nuser first-broken@example.com'

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]
    [ -f "${MSMTP_CONF}.pre-migration" ]

    # Corrupt MSMTP_CONF again after the first (successful, real-msmtp-valid) migration.
    write_msmtp_conf_direct $'account other\nuser second-broken@example.com'

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    # Backup must still hold the original pre-migration content, not the second corruption.
    run sudo -n grep -q "first-broken@example.com" "${MSMTP_CONF}.pre-migration"
    [ "$status" -eq 0 ]
    run sudo -n grep -q "second-broken@example.com" "${MSMTP_CONF}.pre-migration"
    [ "$status" -ne 0 ]
    # And the live (broken) file itself must be left untouched rather than silently overwritten.
    run sudo -n grep -q "second-broken@example.com" "$MSMTP_CONF"
    [ "$status" -eq 0 ]
}

@test "e2e migration: mail_sender_cmd selects msmtp post-migration and real msmtp confirms it" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    run mail_sender_cmd
    [ "$status" -eq 0 ]
    [ "$output" = "msmtp" ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]

    run mail_read_recipient_from_config
    [ "$status" -eq 0 ]
    [ "$output" = "user@gmail.com" ]
    [ "$output" = "$(real_msmtp_field user)" ]
}

@test "e2e migration: msmtp's implicit-default compatibility form is recognized as already migrated" {
    write_ssmtp_conf \
        "root=stale@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=stale@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"

    # Bare top-level directives, no "defaults"/"account" keyword at all — real msmtp treats this
    # as an implicit "default" account (verified against the real binary).
    printf 'host smtp.gmail.com\nport 587\nfrom implicit@gmail.com\nuser implicit@gmail.com\npassword secret\n' \
        > "$MSMTP_CONF"
    chmod 600 "$MSMTP_CONF"

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    # Untouched: migration must not have overwritten the implicit-form account.
    [ "$(real_msmtp_field user)" = "implicit@gmail.com" ]
    [ ! -e "${MSMTP_CONF}.pre-migration" ]
}

# --- Additional sad-path / guard-branch coverage -----------------------------------------------

@test "e2e migration: no-op when SSMTP_CONF does not exist at all" {
    rm -f "$SSMTP_CONF"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]
    [ ! -e "$MSMTP_CONF" ]
}

@test "e2e migration: no-op when ssmtp.conf is empty (no AuthUser/AuthPass)" {
    : > "$SSMTP_CONF"
    chmod 600 "$SSMTP_CONF"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]
    [ ! -e "$MSMTP_CONF" ]
}

@test "e2e migration: no-op when ssmtp.conf has only a partial credential (password missing)" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com"
    # No AuthPass line at all.

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]
    [ ! -e "$MSMTP_CONF" ]
}

@test "e2e migration: reads root:mail-owned ssmtp.conf via the sudo -n cat fallback" {
    # Direct (non-sudo) read of AuthUser/AuthPass must fail here — this test only proves anything
    # if the file genuinely isn't readable without elevation. Also exercises the conf_text-based
    # hub/UseSTARTTLS/UseTLS parsing sub-path (not just the email/password extraction), since once
    # the sudo fallback fires, migrate reuses that same in-memory content for everything else too.
    write_ssmtp_conf_root_owned \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:465" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseTLS=YES"
    run grep -q "AuthPass=" "$SSMTP_CONF"
    [ "$status" -ne 0 ]

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field user)" = "user@gmail.com" ]
    [ "$(real_msmtp_field host)" = "smtp.gmail.com" ]
    [ "$(real_msmtp_field port)" = "465" ]
    [ "$(real_msmtp_field tls)" = "on" ]
    [ "$(real_msmtp_field tls_starttls)" = "off" ]
}

@test "e2e migration: UseTLS=YES on a non-465 port enables TLS without STARTTLS" {
    # Isolates the plain UseTLS=YES branch from the port-465-implies-TLS special case.
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.example.com:2525" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseTLS=YES"

    run migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field port)" = "2525" ]
    [ "$(real_msmtp_field tls)" = "on" ]
    [ "$(real_msmtp_field tls_starttls)" = "off" ]
}

@test "e2e migration: root-invocation uses plain cp for the backup (no sudo elevation needed)" {
    # When migrate runs as root (e.g. a root cron job), the sudo-elevation guard is skipped
    # entirely and the backup uses plain `cp -p` instead of `sudo -n cp -p` — a distinct code
    # path from every other test here, which all run as a non-root user.
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"
    write_msmtp_conf_direct $'account other\nuser leftover@example.com'

    run sudo -n bash -c "
        export TEST_MODE=true REAL_DEPS=1
        export SSMTP_CONF='$SSMTP_CONF' REVALIASES='$REVALIASES' MSMTP_CONF='$MSMTP_CONF'
        source ./lib/os_pkg.sh
        source ./lib/mail_send.sh
        [ \"\$(id -u)\" -eq 0 ] || exit 99
        migrate_mail_config_to_msmtp
    "
    [ "$status" -eq 0 ]

    [ -f "${MSMTP_CONF}.pre-migration" ]
    run sudo -n grep -q "leftover@example.com" "${MSMTP_CONF}.pre-migration"
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field user)" = "user@gmail.com" ]
}

@test "e2e migration: no-op when the msmtp binary is not installed" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"

    run run_without_binary msmtp migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]
    [ ! -e "$MSMTP_CONF" ]
}

@test "e2e migration: aborts without writing MSMTP_CONF when passwordless sudo is unavailable" {
    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"
    [ "$(id -u)" -ne 0 ] || skip "requires running as a non-root user (sudo elevation is what's under test)"

    run run_without_passwordless_sudo migrate_mail_config_to_msmtp
    [ "$status" -eq 0 ]
    [ ! -e "$MSMTP_CONF" ]
}

@test "e2e mail_sender_cmd: prefers real ssmtp when msmtp has no usable default account" {
    write_msmtp_conf_direct $'account other\nuser unusable@example.com'

    run mail_sender_cmd
    [ "$status" -eq 0 ]
    [ "$output" = "ssmtp" ]
}

@test "e2e mail_sender_cmd: falls back to msmtp as a last resort when neither is usable" {
    write_msmtp_conf_direct $'account other\nuser unusable@example.com'

    run run_without_binary ssmtp mail_sender_cmd
    [ "$status" -eq 0 ]
    [ "$output" = "msmtp" ]
}

@test "e2e mail_sender_cmd: selects msmtp when it has a real-msmtp-valid default account" {
    run write_mail_config_msmtp "picked@gmail.com" "secret"
    [ "$status" -eq 0 ]
    run real_msmtp_default_ok
    [ "$status" -eq 0 ]

    run mail_sender_cmd
    [ "$status" -eq 0 ]
    [ "$output" = "msmtp" ]
}

@test "e2e mail_read_recipient_from_config: falls back to ssmtp's root= when msmtp has no user" {
    write_ssmtp_conf \
        "root=fallback@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=fallback@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"
    write_msmtp_conf_direct $'account other\nuser unusable@example.com'

    run mail_read_recipient_from_config
    [ "$status" -eq 0 ]
    [ "$output" = "fallback@gmail.com" ]
}

@test "e2e mail_read_recipient_from_config: fails when neither config has a resolvable recipient" {
    rm -f "$SSMTP_CONF"

    run mail_read_recipient_from_config
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# --- Default-account resolution semantics, each independently confirmed against the real msmtp
# --- binary's own -P output/exit code before being asserted here (see git history / PR discussion
# --- for the exact `msmtp --file=... --account=default -P` transcripts).

@test "e2e resolver: spaced inheritance 'account default : parent'" {
    rm -f "$SSMTP_CONF"
    write_msmtp_conf_direct $'account personal\nhost smtp.gmail.com\nuser spaced@gmail.com\npassword secret\n\naccount default : personal'

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    run _msmtp_has_default_account
    [ "$status" -eq 0 ]
    run mail_read_recipient_from_config
    [ "$output" = "spaced@gmail.com" ]
}

@test "e2e resolver: attached inheritance 'account default: parent' (no space before colon)" {
    rm -f "$SSMTP_CONF"
    write_msmtp_conf_direct $'account personal\nhost smtp.gmail.com\nuser attached@gmail.com\npassword secret\n\naccount default: personal'

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    run mail_read_recipient_from_config
    [ "$output" = "attached@gmail.com" ]
}

@test "e2e resolver: comma-separated multi-parent list, later parent wins on conflict" {
    rm -f "$SSMTP_CONF"
    conf=$'account personal\nhost smtp.gmail.com\nuser personal@gmail.com\n\n'
    conf+=$'account work\nhost smtp.gmail.com\nuser work@gmail.com\npassword secret\n\n'
    conf+='account default : personal, work'
    write_msmtp_conf_direct "$conf"

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    # "work" is listed last, so it wins for the conflicting "user" field.
    [ "$(real_msmtp_field user)" = "work@gmail.com" ]
    run mail_read_recipient_from_config
    [ "$output" = "work@gmail.com" ]
}

@test "e2e resolver: chained multi-level inheritance (default -> work -> personal)" {
    rm -f "$SSMTP_CONF"
    conf=$'account personal\nhost smtp.gmail.com\nuser chained@gmail.com\npassword secret\n\n'
    conf+=$'account work : personal\n\naccount default : work'
    write_msmtp_conf_direct "$conf"

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field user)" = "chained@gmail.com" ]
}

@test "e2e resolver: field resolved purely from the top-level defaults block" {
    rm -f "$SSMTP_CONF"
    conf=$'defaults\nauth on\nhost smtp.fromdefaults.com\n\n'
    conf+=$'account default\nuser fromdefaults@gmail.com\npassword secret'
    write_msmtp_conf_direct "$conf"

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field host)" = "smtp.fromdefaults.com" ]
    run _msmtp_has_default_account
    [ "$status" -eq 0 ]
}

@test "e2e resolver: a defaults block declared after account default does not retroactively apply" {
    rm -f "$SSMTP_CONF"
    write_msmtp_conf_direct $'account default\nhost smtp.gmail.com\nuser early@gmail.com\npassword secret\n\ndefaults\nport 2525'

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    # Real msmtp's own default port (25), not the later defaults block's 2525.
    [ "$(real_msmtp_field port)" = "25" ]
}

@test "e2e resolver: a bare 'defaults' block with no account line is not a usable default account" {
    rm -f "$SSMTP_CONF"
    write_msmtp_conf_direct $'defaults\nhost smtp.gmail.com\nuser nouser@gmail.com'

    run real_msmtp_default_ok
    [ "$status" -ne 0 ]
    run _msmtp_has_default_account
    [ "$status" -ne 0 ]
}

@test "e2e resolver: an undeclared parent invalidates the whole account (matches real msmtp's rejection)" {
    rm -f "$SSMTP_CONF"
    conf=$'account personal\nhost smtp.gmail.com\nuser real@gmail.com\npassword secret\n\n'
    conf+='account default : personal, ghost'
    write_msmtp_conf_direct "$conf"

    run real_msmtp_default_ok
    [ "$status" -ne 0 ]
    run _msmtp_has_default_account
    [ "$status" -ne 0 ]
}

@test "e2e resolver: a forward-referenced parent (declared later in the file) invalidates the account" {
    rm -f "$SSMTP_CONF"
    write_msmtp_conf_direct $'account default : later\nuser should-not-resolve@gmail.com\n\naccount later\nhost smtp.gmail.com'

    run real_msmtp_default_ok
    [ "$status" -ne 0 ]
    run _msmtp_has_default_account
    [ "$status" -ne 0 ]
}

@test "e2e resolver: space-separated (no comma) parent list is treated as one illegal account name" {
    rm -f "$SSMTP_CONF"
    conf=$'account personal\nhost smtp.gmail.com\nuser x@gmail.com\n\n'
    conf+=$'account other\nhost smtp.example.com\n\naccount default : personal other'
    write_msmtp_conf_direct "$conf"

    run real_msmtp_default_ok
    [ "$status" -ne 0 ]
    run _msmtp_has_default_account
    [ "$status" -ne 0 ]
}

# --- Full end-to-end automated-update proof: this is exactly what runs on a real Pi, unattended,
# --- when update_self.sh's weekly cron job finds a new release and re-execs the staged
# --- install.sh --update. No stdin is provided (piped from /dev/null) to prove no prompt of any
# --- kind can be waited on: if any code path in this chain tried to read interactive input, this
# --- test would hang (and bats/CI would time it out) instead of completing.
@test "e2e automated update: 'install.sh --update' migrates a legacy ssmtp setup with zero user input" {
    local update_install_dir="/tmp/e2e-update-migrate-$$"
    rm -rf "$update_install_dir"

    write_ssmtp_conf \
        "root=user@gmail.com" \
        "mailhub=smtp.gmail.com:587" \
        "AuthUser=user@gmail.com" \
        "AuthPass=secret" \
        "UseSTARTTLS=YES"
    [ ! -e "$MSMTP_CONF" ]

    run env INSTALL_DIR="$update_install_dir" SSMTP_CONF="$SSMTP_CONF" \
        REVALIASES="$REVALIASES" MSMTP_CONF="$MSMTP_CONF" TEST_MODE=true \
        bash ./install.sh --update < /dev/null
    [ "$status" -eq 0 ]

    run real_msmtp_default_ok
    [ "$status" -eq 0 ]
    [ "$(real_msmtp_field user)" = "user@gmail.com" ]
    [ "$(real_msmtp_field host)" = "smtp.gmail.com" ]

    rm -rf "$update_install_dir"
}
