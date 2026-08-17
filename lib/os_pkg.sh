#!/usr/bin/env bash
# OS family detection and multi-package-manager helpers (apt / dnf / pacman).
# shellcheck shell=bash

# Cron-friendly PATH seed. Skip when MOCK_DIR is set so BATS path_hiding stays effective
# (re-appending /usr/bin would resurrect real host binaries such as Fedora's 7z).

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

rpi_ensure_cron_path() {
    if [ -n "${MOCK_DIR:-}" ]; then
        return 0
    fi
    export PATH="${PATH}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}
rpi_ensure_cron_path

_trim_os_release_value() {
    local value="$1"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s' "$value"
}

_lookup_os_family_exact() {
    local candidate="$1"
    case "$candidate" in
        ubuntu | debian | linuxmint | pop | kali | elementary | raspbian) echo "debian" ;;
        fedora | rhel | centos | rocky | almalinux | amzn) echo "redhat" ;;
        arch | manjaro | endeavouros | artix | steamos) echo "arch" ;;
        *) return 1 ;;
    esac
}

_lookup_os_family_like() {
    local candidate="$1"
    case "$candidate" in
        *ubuntu* | *debian* | *raspbian*) echo "debian" ;;
        *fedora* | *rhel* | *centos* | *rocky* | *almalinux* | *amzn*) echo "redhat" ;;
        *arch* | *manjaro* | *endeavouros* | *artix*) echo "arch" ;;
        *) return 1 ;;
    esac
}

detect_os_family() {
    local os_id="${INSTALL_OS_ID:-}" os_like="${INSTALL_OS_ID_LIKE:-}" family key value

    if [ -n "$os_id" ]; then
        family=$(_lookup_os_family_exact "$os_id") && {
            echo "$family"
            return 0
        }
        family=$(_lookup_os_family_like "$os_like") && {
            echo "$family"
            return 0
        }
        return 1
    fi

    if [ -r /etc/os-release ]; then
        while IFS='=' read -r key value; do
            case "$key" in
                ID) os_id=$(_trim_os_release_value "$value") ;;
                ID_LIKE) os_like=$(_trim_os_release_value "$value") ;;
            esac
        done < /etc/os-release
        family=$(_lookup_os_family_exact "$os_id") && {
            echo "$family"
            return 0
        }
        family=$(_lookup_os_family_like "$os_like") && {
            echo "$family"
            return 0
        }
    fi

    if command -v apt-get > /dev/null 2>&1 || command -v apt > /dev/null 2>&1; then
        echo "debian"
        return 0
    fi
    if command -v dnf > /dev/null 2>&1 || command -v yum > /dev/null 2>&1; then
        echo "redhat"
        return 0
    fi
    if command -v pacman > /dev/null 2>&1; then
        echo "arch"
        return 0
    fi
    return 1
}

_current_os_id() {
    local key value os_id="${INSTALL_OS_ID:-}"
    if [ -n "$os_id" ]; then
        printf '%s' "$os_id"
        return 0
    fi
    if [ -r /etc/os-release ]; then
        while IFS='=' read -r key value; do
            if [ "$key" = "ID" ]; then
                _trim_os_release_value "$value"
                return 0
            fi
        done < /etc/os-release
    fi
    return 1
}

# Map logical dependency names to family package names (space-separated if multiple).
resolve_pkg_names() {
    local logical="$1"
    local family os_id
    family=$(detect_os_family) || family="debian"
    os_id=$(_current_os_id) || os_id=""

    case "$family:$logical" in
        *:curl) echo "curl" ;;
        debian:whiptail) echo "whiptail" ;;
        redhat:whiptail) echo "newt" ;;
        arch:whiptail) echo "libnewt" ;;
        debian:mail-transport) echo "ssmtp mailutils" ;;
        redhat:mail-transport) echo "msmtp s-nail" ;;
        arch:mail-transport) echo "msmtp s-nail" ;;
        debian:ssmtp) echo "ssmtp" ;;
        redhat:ssmtp | arch:ssmtp) echo "msmtp" ;;
        *:fwupd) echo "fwupd" ;;
        *:nvme-cli) echo "nvme-cli" ;;
        debian:p7zip) echo "p7zip-full" ;;
        # Fedora renamed p7zip → 7zip; RHEL/Rocky/Alma still ship p7zip.
        redhat:p7zip)
            case "$os_id" in
                fedora) echo "7zip" ;;
                *) echo "p7zip" ;;
            esac
            ;;
        arch:p7zip) echo "p7zip" ;;
        *:cpio) echo "cpio" ;;
        *:file) echo "file" ;;
        *:gzip) echo "gzip" ;;
        debian:rpi-eeprom) echo "rpi-eeprom" ;;
        *:rpi-eeprom) echo "" ;;
        *) echo "$logical" ;;
    esac
}

# Command that indicates a logical dep is present.
_logical_cmd() {
    case "$1" in
        curl) echo "curl" ;;
        whiptail) echo "whiptail" ;;
        mail-transport | ssmtp)
            if command -v ssmtp > /dev/null 2>&1; then
                echo "ssmtp"
            else
                echo "msmtp"
            fi
            ;;
        fwupd) echo "fwupdmgr" ;;
        nvme-cli) echo "nvme" ;;
        p7zip) echo "7z" ;;
        cpio) echo "cpio" ;;
        file) echo "file" ;;
        gzip) echo "gzip" ;;
        rpi-eeprom) echo "rpi-eeprom-update" ;;
        *) echo "$1" ;;
    esac
}

logical_is_installed() {
    local cmd
    cmd=$(_logical_cmd "$1")
    command -v "$cmd" > /dev/null 2>&1
}

has_mail_sender() {
    command -v ssmtp > /dev/null 2>&1 || command -v msmtp > /dev/null 2>&1
}

pkg_refresh() {
    local family
    family=$(detect_os_family) || return 1
    case "$family" in
        debian) sudo DEBIAN_FRONTEND=noninteractive apt-get update ;;
        redhat)
            if command -v dnf > /dev/null 2>&1; then
                sudo dnf -y makecache
            else
                sudo yum makecache
            fi
            ;;
        arch) sudo pacman -Sy --noconfirm ;;
        *) return 1 ;;
    esac
}

pkg_install_raw() {
    local family
    family=$(detect_os_family) || return 1
    [ "$#" -eq 0 ] && return 0
    case "$family" in
        debian) sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        redhat)
            if command -v dnf > /dev/null 2>&1; then
                sudo dnf install -y "$@"
            else
                sudo yum install -y "$@"
            fi
            ;;
        arch) sudo pacman -S --noconfirm --needed "$@" ;;
        *) return 1 ;;
    esac
}

# Install logical deps (curl, whiptail, mail-transport, fwupd, ...).
pkg_install() {
    local logical pkgs pkg pkg_list missing=()
    for logical in "$@"; do
        if logical_is_installed "$logical"; then
            continue
        fi
        pkgs=$(resolve_pkg_names "$logical")
        if [ -z "$pkgs" ]; then
            _pi_echof "Warning: no package mapping for '%s' on this OS family; skipping." "$logical" >&2
            continue
        fi
        read -r -a pkg_list <<< "$pkgs"
        for pkg in "${pkg_list[@]}"; do
            missing+=("$pkg")
        done
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    pkg_refresh || true
    pkg_install_raw "${missing[@]}"
}

pkg_update_system() {
    local family
    family=$(detect_os_family) || return 1
    case "$family" in
        debian)
            echo "--- Running 'sudo apt-get update' ---"
            sudo DEBIAN_FRONTEND=noninteractive apt-get update 2>&1
            echo ""
            echo "--- Running 'sudo apt-get full-upgrade -y' ---"
            sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y 2>&1
            echo ""
            echo "--- Running 'sudo apt-get autoremove -y' ---"
            sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>&1
            ;;
        redhat)
            if command -v dnf > /dev/null 2>&1; then
                echo "--- Running 'sudo dnf upgrade -y' ---"
                sudo dnf upgrade -y 2>&1
                echo ""
                echo "--- Running 'sudo dnf autoremove -y' ---"
                sudo dnf autoremove -y 2>&1
            else
                echo "--- Running 'sudo yum update -y' ---"
                sudo yum update -y 2>&1
            fi
            ;;
        arch)
            echo "--- Running 'sudo pacman -Syu --noconfirm' ---"
            sudo pacman -Syu --noconfirm 2>&1
            ;;
        *)
            _pi_echo "Unsupported OS family for system update." >&2
            return 1
            ;;
    esac
}
