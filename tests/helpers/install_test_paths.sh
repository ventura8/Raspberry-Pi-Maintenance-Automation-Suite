#!/usr/bin/env bash
# Test-only entry for install.sh with per-test mail config paths, INSTALL_DIR and RAW_URL.
# install.sh pins SSMTP_CONF / REVALIASES / MSMTP_CONF to /etc and INSTALL_DIR to the root-owned
# default, ignores the environment for all of them, and only accepts a RAW_URL for this repository
# (main or a vX.Y.Z tag). A test that needs mock values sources this helper instead: it captures
# the exported values, sources install.sh (INSTALL_SH, default ./install.sh), then re-points them
# and re-resolves the helper libs against the test INSTALL_DIR. Production never runs it.
#   source ./tests/helpers/install_test_paths.sh   # functions only, like `source ./install.sh`
#   bash tests/helpers/install_test_paths.sh --update   # like `bash ./install.sh --update`

_test_ssmtp_conf="${SSMTP_CONF:-}"
_test_revaliases="${REVALIASES:-}"
_test_msmtp_conf="${MSMTP_CONF:-}"
_test_install_dir="${INSTALL_DIR:-}"
_test_raw_url="${RAW_URL:-}"

# shellcheck source=../../install.sh
source "${INSTALL_SH:-./install.sh}" 2> /dev/null

if [[ -n "$_test_ssmtp_conf" ]]; then
    SSMTP_CONF="$_test_ssmtp_conf"
fi
if [[ -n "$_test_revaliases" ]]; then
    REVALIASES="$_test_revaliases"
fi
if [[ -n "$_test_msmtp_conf" ]]; then
    MSMTP_CONF="$_test_msmtp_conf"
fi
if [[ -n "$_test_raw_url" ]]; then
    RAW_URL="$_test_raw_url"
fi
if [[ -n "$_test_install_dir" ]]; then
    INSTALL_DIR="$_test_install_dir"
    # install.sh resolved its helpers for the pinned default; redo it for the test tree (same
    # _install_src_trusted rules, so planted-lib tests still exercise the trust check).
    _source_install_libs > /dev/null 2>&1 || true
fi
unset _test_ssmtp_conf _test_revaliases _test_msmtp_conf _test_install_dir _test_raw_url

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_main "$@"
fi
