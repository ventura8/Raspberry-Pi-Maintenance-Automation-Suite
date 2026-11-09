#!/usr/bin/env bash
# Test-only entry for install.sh with per-test mail config paths.
# install.sh pins SSMTP_CONF / REVALIASES / MSMTP_CONF to /etc and ignores the environment, so a
# test that needs mock paths sources this helper instead: it captures the exported values, sources
# install.sh (INSTALL_SH, default ./install.sh), then re-points the paths. Production never runs it.
#   source ./tests/helpers/install_test_paths.sh   # functions only, like `source ./tests/helpers/install_test_paths.sh`
#   bash tests/helpers/install_test_paths.sh --update   # like `bash ./install.sh --update`

_test_ssmtp_conf="${SSMTP_CONF:-}"
_test_revaliases="${REVALIASES:-}"
_test_msmtp_conf="${MSMTP_CONF:-}"

# shellcheck source=../../install.sh
source "${INSTALL_SH:-./install.sh}"

if [[ -n "$_test_ssmtp_conf" ]]; then
    SSMTP_CONF="$_test_ssmtp_conf"
fi
if [[ -n "$_test_revaliases" ]]; then
    REVALIASES="$_test_revaliases"
fi
if [[ -n "$_test_msmtp_conf" ]]; then
    MSMTP_CONF="$_test_msmtp_conf"
fi
unset _test_ssmtp_conf _test_revaliases _test_msmtp_conf

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_main "$@"
fi
