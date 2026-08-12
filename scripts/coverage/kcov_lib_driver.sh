#!/usr/bin/env bash
# Exhaustive kcov entry for lib/os_pkg.sh and lib/mail_send.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=../../tests/setup_mocks.sh
source ./tests/setup_mocks.sh
# shellcheck source=../../lib/os_pkg.sh
source ./lib/os_pkg.sh
# shellcheck source=../../lib/mail_send.sh
source ./lib/mail_send.sh

# Isolate PATH in a function (local) so shellcheck does not warn about subshell exports.
_with_path() {
    local PATH="$1"
    shift
    hash -r 2> /dev/null || true
    "$@"
}

_trim_os_release_value '"quoted"' > /dev/null || true
_trim_os_release_value "'quoted'" > /dev/null || true
_lookup_os_family_exact ubuntu > /dev/null || true
_lookup_os_family_exact fedora > /dev/null || true
_lookup_os_family_exact arch > /dev/null || true
_lookup_os_family_exact nosuch || true
_lookup_os_family_like "ubuntu debian" > /dev/null || true
_lookup_os_family_like "fedora rhel" > /dev/null || true
_lookup_os_family_like "arch linux" > /dev/null || true
_lookup_os_family_like "unknownos" || true

os_ids=(
    ubuntu debian linuxmint pop kali elementary raspbian
    fedora rhel centos rocky almalinux amzn
    arch manjaro endeavouros artix steamos
)
for id in "${os_ids[@]}"; do
    INSTALL_OS_ID="$id" INSTALL_OS_ID_LIKE=""
    detect_os_family > /dev/null
done

INSTALL_OS_ID="custom" INSTALL_OS_ID_LIKE="debian"
detect_os_family > /dev/null
INSTALL_OS_ID="custom" INSTALL_OS_ID_LIKE="fedora rhel"
detect_os_family > /dev/null
INSTALL_OS_ID="custom" INSTALL_OS_ID_LIKE="arch"
detect_os_family > /dev/null
INSTALL_OS_ID="custom" INSTALL_OS_ID_LIKE="unknown"
detect_os_family > /dev/null || true

unset INSTALL_OS_ID INSTALL_OS_ID_LIKE
detect_os_family > /dev/null || true

# Force /etc/os-release + command fallbacks via a fake os-release and empty PATH managers.
FAKE_OS=$(mktemp -d)
cat > "$FAKE_OS/os-release" << 'EOF'
ID=notarealos
ID_LIKE=alsonotreal
EOF
# detect_os_family reads /etc/os-release; override by binding via INSTALL_OS empty and stubbing file is hard —
# instead call fallbacks through a subshell with shadowed detect helpers already covered above.
# Cover manager fallbacks by unsetting ID and temporarily removing apt/dnf/pacman from PATH.
_cover_detect_no_managers() {
    unset INSTALL_OS_ID INSTALL_OS_ID_LIKE
    mkdir -p "$FAKE_OS/bin"
    detect_os_family > /dev/null || true
}
_with_path "$FAKE_OS/bin" _cover_detect_no_managers

for family_id in debian fedora arch; do
    INSTALL_OS_ID="$family_id" INSTALL_OS_ID_LIKE=""
    for logical in curl whiptail mail-transport ssmtp fwupd nvme-cli p7zip cpio file gzip rpi-eeprom unknownpkg; do
        resolve_pkg_names "$logical" > /dev/null
        _logical_cmd "$logical" > /dev/null || true
        logical_is_installed "$logical" || true
    done
    pkg_refresh || true
    pkg_install_raw || true
    pkg_install_raw curl || true
    pkg_install curl mail-transport whiptail || true
    pkg_install curl || true
    pkg_update_system || true
done

INSTALL_OS_ID=fedora INSTALL_OS_ID_LIKE=""
resolve_pkg_names rpi-eeprom > /dev/null
pkg_install rpi-eeprom || true

# yum fallbacks (redhat without dnf)
INSTALL_OS_ID=fedora INSTALL_OS_ID_LIKE=""
YUMBIN=$(mktemp -d)
cat > "$YUMBIN/yum" << 'EOF'
#!/bin/bash
echo "[stub] yum $*"
exit 0
EOF
chmod +x "$YUMBIN/yum"
# Hide dnf; keep yum + mocks sudo
_cover_yum_fallback() {
    pkg_refresh || true
    pkg_install_raw curl || true
    pkg_update_system || true
}
_with_path "$YUMBIN:$MOCK_DIR:/usr/bin:/bin" _cover_yum_fallback

# unsupported family for pkg_update_system / pkg_refresh / pkg_install_raw
INSTALL_OS_ID=custom INSTALL_OS_ID_LIKE=unknown
pkg_refresh || true
pkg_install_raw curl || true
pkg_update_system || true

# mail-transport logical cmd when only msmtp exists
MSBIN=$(mktemp -d)
cat > "$MSBIN/msmtp" << 'EOF'
#!/bin/bash
if [ "$1" = "--account=default" ] || [ "$1" = "-t" ] || [ "$#" -eq 0 ]; then
  cat >/dev/null
  exit 0
fi
cat >/dev/null
exit 0
EOF
chmod +x "$MSBIN/msmtp"
_cover_msmtp_mail() {
    # shellcheck source=../../lib/os_pkg.sh
    source ./lib/os_pkg.sh
    # shellcheck source=../../lib/mail_send.sh
    source ./lib/mail_send.sh
    _logical_cmd mail-transport
    has_mail_sender || true
    mail_sender_cmd || true
    write_mail_config "ms@x.com" "pw" || true
    body=$(mktemp)
    echo "ms body" > "$body"
    send_mail "ms@x.com" "subj" "from" "$body" || true
    rm -f "$body"
}
_with_path "$MSBIN:/usr/bin:/bin" _cover_msmtp_mail

has_mail_sender || true
mail_sender_cmd || true

SSMTP_CONF="$MOCK_FS/etc/ssmtp/ssmtp.conf"
REVALIASES="$MOCK_FS/etc/ssmtp/revaliases"
MSMTP_CONF="$MOCK_FS/etc/msmtprc"
mkdir -p "$(dirname "$SSMTP_CONF")" "$(dirname "$MSMTP_CONF")"
: > "$SSMTP_CONF"
write_mail_config_ssmtp "a@b.com" "pw" || true
write_mail_config_msmtp "a@b.com" "pw" || true
write_mail_config "a@b.com" "pw" || true

mail_read_recipient_from_config || true
echo "root=onlyroot@x.com" > "$SSMTP_CONF"
mail_read_recipient_from_config || true
echo "AuthUser=auth@x.com" > "$SSMTP_CONF"
mail_read_recipient_from_config || true
rm -f "$SSMTP_CONF"
echo "user msuser@x.com" > "$MSMTP_CONF"
mail_read_recipient_from_config || true
rm -f "$MSMTP_CONF"
mail_read_recipient_from_config || true

body=$(mktemp)
echo "body" > "$body"
send_mail "a@b.com" "subj" "from" "$body" || true
send_mail "a@b.com" "subj" "from" - <<< "stdin body" || true
rm -f "$body"

mail_sender_cmd() { return 1; }
send_mail "a@b.com" "subj" "from" /dev/null || true
unset -f mail_sender_cmd
# shellcheck source=../../lib/mail_send.sh
source ./lib/mail_send.sh

_rpi_source_lib "$ROOT/scripts/update_pi_os.sh" "os_pkg.sh" || true
_rpi_source_lib "$ROOT/scripts/update_pi_os.sh" "missing.sh" || true
_rpi_source_lib "$ROOT/install.sh" "os_pkg.sh" || true

# Force pkg_install to install something considered missing
INSTALL_OS_ID=debian INSTALL_OS_ID_LIKE=""
logical_is_installed() { return 1; }
pkg_install curl || true
unset -f logical_is_installed
# shellcheck source=../../lib/os_pkg.sh
source ./lib/os_pkg.sh

rm -rf "$FAKE_OS" "$YUMBIN" "$MSBIN"
echo "lib coverage driver done"
