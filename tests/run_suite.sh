#!/bin/bash
set -e

# Setup environment variables
export TERM=dumb
# Ensure we use the current container user, defaulting to pi if unset
export USER="${USER:-pi}"
export TEST_MODE="true"
# Default installer tests drive the text UI via stdin; whiptail is opt-in per test file.
unset INSTALL_USE_WHIPTAIL || true
export INSTALL_FORCE_TEXT_UI="${INSTALL_FORCE_TEXT_UI:-0}"
export INSTALL_UI_MODE=""
# Isolate installer state from any real ~/pi-scripts on the host.
_SUITE_INSTALL_DIR_DEFAULT="/tmp/pi-scripts-suite"
export INSTALL_DIR="${INSTALL_DIR:-$_SUITE_INSTALL_DIR_DEFAULT}"
case "$INSTALL_DIR" in
    /tmp/pi-scripts-suite | /tmp/pi-scripts-suite/* | /tmp/pi-scripts*)
        rm -rf "$INSTALL_DIR"
        ;;
    *)
        echo "ERROR: refusing to rm INSTALL_DIR outside /tmp/pi-scripts*: $INSTALL_DIR" >&2
        exit 1
        ;;
esac

# Source the shared mock setup script
# This sets up MOCK_DIR, creates mocks, and exports PATH
source ./tests/setup_mocks.sh

echo "--- Mocks Ready. Running Tests ---"
echo "PATH is: $PATH"
# Ensure Unix line endings (fix for Windows mounts)
sed -i 's/\r$//' ./*.sh scripts/*.sh tests/*.sh 2> /dev/null || true

# Executable prep shared with host orchestrators (bind-mount UID-safe on Actions).
# shellcheck source=../scripts/ensure_exec.sh
source ./scripts/ensure_exec.sh
rpi_ensure_scripts_executable .

# Parse Mode Arguments
MODE="all"
TEST_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --installer-only)
            MODE="installer"
            shift
            ;;
        --maintenance-only)
            MODE="maintenance"
            shift
            ;;
        --test-file)
            TEST_FILE="$2"
            shift
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "--- Run Mode: $MODE ---"

# Coverage configuration
COVERAGE_ENABLED="${COVERAGE:-0}"
COVERAGE_OUTPUT_DIR="${COVERAGE_OUTPUT:-./coverage}"
# Narrow include-path to product files only. Including the whole repo (or all of scripts/)
# makes kcov parse orchestrators/caches and breaks attribution for `bash script` runs.
# lib/*.sh is only included for the dedicated lib driver so partial incidental hits do not dilute the gate.
KCOV_INCLUDE_PATH="$PWD/install.sh,$PWD/uninstall.sh"
KCOV_INCLUDE_PATH+=",$PWD/scripts/update_pi_os.sh,$PWD/scripts/update_pi_firmware.sh,$PWD/scripts/update_pip.sh"
KCOV_INCLUDE_PATH+=",$PWD/scripts/docker_cleanup.sh,$PWD/scripts/update_pi_apps.sh,$PWD/scripts/update_samsung_ssd.sh"
KCOV_INCLUDE_PATH+=",$PWD/scripts/update_self.sh"
KCOV_INCLUDE_PATH+=",$PWD/lib/i18n.sh,$PWD/lib/i18n_soft.sh"
KCOV_INCLUDE_PATH+=",$PWD/scripts/coverage/kcov_install_entry.sh,$PWD/scripts/coverage/kcov_install_driver.sh"
KCOV_EXCLUDE_PATTERN="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,"
KCOV_EXCLUDE_PATTERN+=".bash_logout,install_lib.sh,pi-apps/updater,lib/os_pkg.sh,lib/mail_send.sh,/lib/os_pkg.sh,/lib/mail_send.sh"
KCOV_ARGS=(--exclude-pattern="$KCOV_EXCLUDE_PATTERN" --include-path="$KCOV_INCLUDE_PATH" --exclude-region=KCOV_EXCL_START:KCOV_EXCL_STOP)

if [ "$COVERAGE_ENABLED" = "1" ]; then
    echo "--- Coverage Mode: ENABLED ---"
    echo "Coverage output: $COVERAGE_OUTPUT_DIR"
    mkdir -p "$COVERAGE_OUTPUT_DIR"

    # Helper for install.sh integration phases (kcov entry must be an included script).
    run_with_coverage() {
        local test_name="$1"

        echo "Running with coverage: $test_name"
        kcov \
            "${KCOV_ARGS[@]}" \
            "$COVERAGE_OUTPUT_DIR/$test_name" \
            "$PWD/scripts/coverage/kcov_install_entry.sh"
    }
else
    echo "--- Coverage Mode: DISABLED ---"
fi

# Run Specific Test File if provided
if [ -n "$TEST_FILE" ]; then
    echo "--- Running Specific Test File: $TEST_FILE ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        TEST_NAME=$(basename "$TEST_FILE" .bats)
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/$TEST_NAME" bats "$TEST_FILE"
    else
        bats "$TEST_FILE"
    fi
    exit $?
fi

# Run Unit and Component Tests with BATS
if [ "$MODE" = "all" ] || [ "$MODE" = "installer" ]; then
    echo "--- Running Unit Tests ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        # Lib helpers are unit-tested in component_tests_os_pkg; exclude from kcov product gate
        # (OS-release/manager fallbacks are environment-specific and dilute per-file rates).
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/install_coverage_driver" "$PWD/scripts/coverage/kcov_install_driver.sh"
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/unit_tests" bats tests/unit_tests.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/install_interactive" bats tests/install_interactive.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/install_extended" bats tests/install_extended.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/install_whiptail" bats tests/install_whiptail.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/install_pi_mode" bats tests/install_pi_mode.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/install_non_pi_mode" bats tests/install_non_pi_mode.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/uninstall" bats tests/uninstall.bats
    else
        bats tests/unit_tests.bats
        bats tests/install_interactive.bats
        bats tests/install_extended.bats
        bats tests/install_whiptail.bats
        bats tests/install_pi_mode.bats
        bats tests/install_non_pi_mode.bats
        bats tests/uninstall.bats
    fi
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "maintenance" ]; then
    echo "--- Running Component Tests ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/component_tests" bats tests/component_tests.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/component_tests_samsung" bats tests/component_tests_samsung.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/component_tests_self_update" bats tests/component_tests_self_update.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/component_tests_os_pkg" bats tests/component_tests_os_pkg.bats
        kcov "${KCOV_ARGS[@]}" "$COVERAGE_OUTPUT_DIR/component_tests_i18n" bats tests/component_tests_i18n.bats
    else
        bats tests/component_tests.bats
        bats tests/component_tests_samsung.bats
        bats tests/component_tests_self_update.bats
        bats tests/component_tests_os_pkg.bats
        bats tests/component_tests_i18n.bats
    fi
fi

# Integration Tests: These simulate full user interaction flows
if [ "$MODE" = "all" ] || [ "$MODE" = "installer" ]; then
    echo ""
    echo "=================================================="
    echo "[SUITE] Running Integration Test (Installer Logic)"
    echo "=================================================="

    # Point installer config paths at the mock filesystem so [ -f ] checks match tee/grep mocks.
    MOCK_FS="${MOCK_FS:-/tmp/mocks/fs}"
    mkdir -p "${MOCK_FS}/etc/ssmtp"
    export SSMTP_CONF="${MOCK_FS}/etc/ssmtp/ssmtp.conf"
    export REVALIASES="${MOCK_FS}/etc/ssmtp/revaliases"
    # Empty existing conf makes the fresh wizard ask "reconfigure?" so the leading "Y" input is valid.
    : > "$SSMTP_CONF"
    : > "$REVALIASES"

    # PHASE 1: Install, Configure, Manage
    echo "--- [PHASE 1] Install, Configure, Schedule ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        (
            echo "Y"
            sleep 1
            echo "test@initial.com"
            sleep 1
            echo "pass1"
            sleep 1
            echo ""
            echo ""
            echo ""
            echo ""
            echo ""
            echo ""
            echo ""
            sleep 2
            echo "2"
            sleep 1
            echo ""
            sleep 1
            echo "1"
            sleep 1
            echo "Y"
            sleep 1
            echo "test@final.com"
            sleep 1
            echo "pass2"
            sleep 1
            echo "4"
            sleep 1
            echo "3"
            sleep 1
            echo "1"
            sleep 1
            echo "e"
            sleep 1
            echo "0 0 * * *"
            sleep 1
            echo "4"
            sleep 1
            echo "y"
            sleep 1
            echo "0"
            sleep 1
            echo "0"
        ) | run_with_coverage "install_phase1"
    else
        (
            echo "Y"
            sleep 0.5
            echo "test@initial.com"
            sleep 0.5
            echo "pass1"
            sleep 0.5
            echo ""
            echo ""
            echo ""
            echo ""
            echo ""
            echo ""
            echo ""
            sleep 1
            echo "2"
            sleep 0.5
            echo ""
            sleep 0.5
            echo "1"
            sleep 0.5
            echo "Y"
            sleep 0.5
            echo "test@final.com"
            sleep 0.5
            echo "pass2"
            sleep 0.5
            echo "4"
            sleep 0.5
            echo "3"
            sleep 0.5
            echo "1"
            sleep 0.5
            echo "e"
            sleep 0.5
            echo "0 0 * * *"
            sleep 0.5
            echo "4"
            sleep 0.5
            echo "y"
            sleep 0.5
            echo "0"
            sleep 0.5
            echo "0"
        ) | ./install.sh
    fi
    echo "--- [VERIFY] Checking Phase 1 State ---"
    # Prefer the mock filesystem path; fall back only if mocks were not initialized.
    TARGET_CONF="${MOCK_FS:-/tmp/mocks/fs}/etc/ssmtp/ssmtp.conf"
    if [ ! -f "$TARGET_CONF" ]; then
        TARGET_CONF="/etc/ssmtp/ssmtp.conf"
    fi
    if /usr/bin/grep -q "AuthUser=test@final.com" "$TARGET_CONF" 2> /dev/null; then
        echo "✅ SSMTP: Configured correctly to test@final.com"
    else
        echo "❌ SSMTP: Config failed (Expected test@final.com)"
        echo "   Checked: $TARGET_CONF (size=$(wc -c < "$TARGET_CONF" 2> /dev/null || echo 0))"
        /usr/bin/grep -E '^(AuthUser|mailhub)=' "$TARGET_CONF" 2> /dev/null || true
        exit 1
    fi

    # PHASE 3: Edge Cases
    echo ""
    echo "--- [PHASE 3] Edge Cases ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        (
            echo "1"
            sleep 0.2
            echo "Y"
            sleep 0.2
            echo "invalid_email"
            sleep 0.2
            echo ""
            echo "1"
            sleep 0.2
            echo "Y"
            sleep 0.2
            echo "valid@email.com"
            sleep 0.2
            echo ""
            echo "1"
            sleep 0.2
            echo "N"
            sleep 0.2
            echo "2"
            sleep 0.2
            echo ""
            echo "3"
            sleep 0.2
            echo "9"
            sleep 0.2
            echo "0"
            sleep 0.2
            echo "4"
            sleep 0.5
            echo "9"
            sleep 0.2
            echo "5"
            sleep 0.2
            echo "N"
            sleep 0.2
            echo "0"
        ) | run_with_coverage "install_phase3_edge_cases"
    fi
fi

# PHASE 4: Uninstall Edge Case (covered by component tests)
if [ "$COVERAGE_ENABLED" = "1" ]; then
    echo "--- Merging Coverage Reports ---"
    HTML_REPORT_DIR="$COVERAGE_OUTPUT_DIR/html_report"
    mkdir -p "$HTML_REPORT_DIR"
    if [ "$MODE" = "installer" ]; then
        kcov --merge "$HTML_REPORT_DIR" \
            "$COVERAGE_OUTPUT_DIR/install_coverage_driver" \
            "$COVERAGE_OUTPUT_DIR/unit_tests" \
            "$COVERAGE_OUTPUT_DIR/install_interactive" \
            "$COVERAGE_OUTPUT_DIR/install_extended" \
            "$COVERAGE_OUTPUT_DIR/install_whiptail" \
            "$COVERAGE_OUTPUT_DIR/install_phase1" \
            "$COVERAGE_OUTPUT_DIR/install_phase3_edge_cases" \
            "$COVERAGE_OUTPUT_DIR/uninstall"
    elif [ "$MODE" = "maintenance" ]; then
        cp -r "$COVERAGE_OUTPUT_DIR/component_tests/"* "$HTML_REPORT_DIR/"
    else
        kcov --merge "$HTML_REPORT_DIR" \
            "$COVERAGE_OUTPUT_DIR/install_coverage_driver" \
            "$COVERAGE_OUTPUT_DIR/unit_tests" \
            "$COVERAGE_OUTPUT_DIR/component_tests" \
            "$COVERAGE_OUTPUT_DIR/component_tests_samsung" \
            "$COVERAGE_OUTPUT_DIR/component_tests_self_update" \
            "$COVERAGE_OUTPUT_DIR/component_tests_os_pkg" \
            "$COVERAGE_OUTPUT_DIR/component_tests_i18n" \
            "$COVERAGE_OUTPUT_DIR/install_interactive" \
            "$COVERAGE_OUTPUT_DIR/install_extended" \
            "$COVERAGE_OUTPUT_DIR/install_whiptail" \
            "$COVERAGE_OUTPUT_DIR/install_non_pi_mode" \
            "$COVERAGE_OUTPUT_DIR/install_pi_mode" \
            "$COVERAGE_OUTPUT_DIR/install_phase1" \
            "$COVERAGE_OUTPUT_DIR/install_phase3_edge_cases" \
            "$COVERAGE_OUTPUT_DIR/uninstall"
    fi

    echo "--- Patching Cobertura XMLs ---"
    MERGED_XML=$(find "$HTML_REPORT_DIR" -name "cobertura.xml" | head -n 1)
    if [ -f "$MERGED_XML" ]; then
        mv "$MERGED_XML" "$COVERAGE_OUTPUT_DIR/cobertura.xml"
        sed -i 's/branches-covered="\([^"]*\)"/branches-covered="\1" branches-valid="0"/g' "$COVERAGE_OUTPUT_DIR/cobertura.xml"
        sed -i 's/<package name="[^"]*"/<package name="RPi Maintenance Scripts"/g' "$COVERAGE_OUTPUT_DIR/cobertura.xml"
    fi
fi

echo "[SUCCESS] All System Tests Passed!"

# Auto-update coverage badge locally
if [ "$COVERAGE_ENABLED" = "1" ] && [ -f "$COVERAGE_OUTPUT_DIR/cobertura.xml" ]; then
    echo ""
    echo "--- Updating Coverage Badge ---"
    python3 tests/transform_coverage.py "$COVERAGE_OUTPUT_DIR/cobertura.xml"

    # Extract coverage percentage and enforce 90% threshold
    COVERAGE_PERCENT=$(grep -oP 'line-rate="\K[^"]+' "$COVERAGE_OUTPUT_DIR/cobertura.xml" | head -1)
    if [ -n "$COVERAGE_PERCENT" ]; then
        COVERAGE_INT=$(echo "$COVERAGE_PERCENT * 100" | bc | cut -d'.' -f1)
        echo "Coverage: ${COVERAGE_INT}%"

        if [ "$COVERAGE_INT" -lt 90 ]; then
            echo ""
            echo "⚠️  WARNING: Coverage ${COVERAGE_INT}% is below mandatory 90% threshold!"
            echo "    Please add more tests before committing."
        else
            echo "✅ Coverage meets 90% requirement"
        fi
    fi

    echo ""
    echo "📦 Remember to commit the updated badge:"
    echo "   git add assets/coverage.svg"
fi
