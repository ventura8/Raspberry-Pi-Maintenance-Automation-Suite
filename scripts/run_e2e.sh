#!/usr/bin/env bash
# In-container e2e with REAL_DEPS=1 (real packages; minimal hardware mocks).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export REAL_DEPS=1
export TEST_MODE=true
export INSTALL_FORCE_TEXT_UI=1
export INSTALL_DIR="${INSTALL_DIR:-/tmp/pi-scripts-e2e}"
export MATRIX_ALLOW_RM_INSTALL_DIR=1

# shellcheck source=lib/os_pkg.sh
source "$REPO_ROOT/lib/os_pkg.sh"
# shellcheck source=scripts/matrix_install_flow.sh
source "$REPO_ROOT/scripts/matrix_install_flow.sh"

echo "=== E2E: dependency presence ==="
command -v bash > /dev/null
command -v curl > /dev/null
command -v sudo > /dev/null
has_mail_sender || echo "WARN: mail sender not present"
command -v whiptail > /dev/null || echo "WARN: whiptail not present"

echo "=== E2E: bats e2e suite ==="
if [ ! -f tests/e2e/e2e_install.bats ]; then
    echo "ERROR: tests/e2e/e2e_install.bats is missing" >&2
    exit 1
fi
if ! command -v bats > /dev/null 2>&1; then
    echo "ERROR: bats executable is required for e2e" >&2
    exit 1
fi
# shellcheck source=tests/setup_mocks.sh
source ./tests/setup_mocks.sh
bats tests/e2e/*.bats

echo "=== E2E: text fresh install flow ==="
matrix_prepare_install_env
matrix_run_text_fresh_install "e2e@example.com" "app-password-test"
matrix_assert_installed

echo "=== E2E: non-interactive --update ==="
bash ./install.sh --update
matrix_assert_installed

echo "=== E2E: Pi / non-Pi toggles via MOCK_IS_PI ==="
MOCK_IS_PI=true bash -c 'source ./install.sh; [ "$IS_PI" = "true" ]'
MOCK_IS_PI=false bash -c 'source ./install.sh; [ "$IS_PI" = "false" ]'

echo "=== E2E: uninstall ==="
matrix_run_uninstall

echo "E2E completed successfully."
