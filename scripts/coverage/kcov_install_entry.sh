#!/usr/bin/env bash
# kcov entrypoint for install.sh integration phases.
# Must live under the kcov --include-path so PS4/DEBUG attribution tracks sourced product files.
set +e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

# install.sh pins its mail config paths to /etc; keep the suite's mock paths (same contract as
# tests/helpers/install_test_paths.sh, inlined so kcov attribution stays on included files).
_cov_ssmtp_conf="${SSMTP_CONF:-/etc/ssmtp/ssmtp.conf}"
_cov_revaliases="${REVALIASES:-/etc/ssmtp/revaliases}"
_cov_msmtp_conf="${MSMTP_CONF:-/etc/msmtprc}"

# shellcheck source=../../install.sh
source "$ROOT/install.sh"
SSMTP_CONF="$_cov_ssmtp_conf"
REVALIASES="$_cov_revaliases"
MSMTP_CONF="$_cov_msmtp_conf"
install_main "$@"
