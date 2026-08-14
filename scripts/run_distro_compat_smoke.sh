#!/usr/bin/env bash
# Distro compatibility smoke: real text install + --update + uninstall on this OS family.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=lib/os_pkg.sh
source "$REPO_ROOT/lib/os_pkg.sh"
# shellcheck source=scripts/matrix_install_flow.sh
source "$REPO_ROOT/scripts/matrix_install_flow.sh"

_smoke_log() {
    printf '[distro-compat-smoke] %s\n' "$*"
}

_smoke_fail() {
    echo "[distro-compat-smoke] ERROR: $*" >&2
    exit 1
}

_smoke_cleanup() {
    # Best-effort: remove install tree + mail confs if a mid-run assertion fails.
    matrix_cleanup_mail_conf 2> /dev/null || true
    if [ -d "${INSTALL_DIR:-}" ]; then
        MATRIX_ALLOW_RM_INSTALL_DIR=1 matrix_run_uninstall 2> /dev/null || rm -rf "${INSTALL_DIR:-}" 2> /dev/null || true
    fi
}

family=$(detect_os_family) || _smoke_fail "Unable to detect OS family"
_smoke_log "OS family: $family"

for cmd in bash curl sudo; do
    command -v "$cmd" > /dev/null 2>&1 || _smoke_fail "Missing required command: $cmd"
done

logical_is_installed curl || _smoke_fail "curl logical dep missing"
logical_is_installed whiptail || _smoke_log "WARN: whiptail missing (text UI fallback expected)"
has_mail_sender || _smoke_log "WARN: mail sender missing"

_smoke_log "Refreshing package metadata (best effort)"
pkg_refresh || _smoke_log "WARN: pkg_refresh failed (non-fatal for smoke)"

export REAL_DEPS=1
export INSTALL_DIR="${INSTALL_DIR:-/tmp/pi-scripts-compat-smoke}"
export MATRIX_ALLOW_RM_INSTALL_DIR=1
trap '_smoke_cleanup' EXIT
matrix_prepare_install_env

_smoke_log "Running real text-UI fresh install"
matrix_run_text_fresh_install "compat@example.com" "app-password-test"
matrix_assert_installed || _smoke_fail "fresh install assertions failed"
_smoke_log "Fresh install OK (version=$(tr -d '[:space:]' < "$INSTALL_DIR/.version"))"

_smoke_log "Running uninstall after fresh install"
matrix_run_uninstall || _smoke_fail "uninstall after fresh install failed"

_smoke_log "Running non-interactive install.sh --update"
matrix_prepare_install_env
bash ./install.sh --update
matrix_assert_installed || _smoke_fail "--update install assertions failed"

_smoke_log "Running uninstall after --update"
matrix_run_uninstall || _smoke_fail "uninstall after --update failed"

trap - EXIT
matrix_cleanup_mail_conf 2> /dev/null || true

_smoke_log "Compat smoke passed on family=$family"
