#!/usr/bin/env bash
# kcov entrypoint for install.sh integration phases.
# Must live under the kcov --include-path so PS4/DEBUG attribution tracks sourced product files.
set +e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

# shellcheck source=../../install.sh
source "$ROOT/install.sh"
install_main "$@"
