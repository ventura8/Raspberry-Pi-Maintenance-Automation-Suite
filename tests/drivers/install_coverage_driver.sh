#!/usr/bin/env bash
# Compatibility shim: coverage entry moved under scripts/coverage/ for kcov include-path.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../scripts/coverage/kcov_install_driver.sh
source "$ROOT/scripts/coverage/kcov_install_driver.sh"
