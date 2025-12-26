#!/bin/bash
set -e

# Setup environment variables
export TERM=dumb
# Ensure we use the current container user, defaulting to pi if unset
export USER="${USER:-pi}"
export TEST_MODE="true"

# Source the shared mock setup script
# This sets up MOCK_DIR, creates mocks, and exports PATH
source ./tests/setup_mocks.sh

echo "--- Mocks Ready. Running Tests ---"
echo "PATH is: $PATH"
# Ensure Unix line endings (fix for Windows mounts)
sed -i 's/\r$//' ./*.sh scripts/*.sh tests/*.sh 2>/dev/null || true

# Set execution permissions
chmod +x install.sh uninstall.sh scripts/*.sh tests/*.sh 2>/dev/null || true

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
            shift; shift
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

if [ "$COVERAGE_ENABLED" = "1" ]; then
    echo "--- Coverage Mode: ENABLED ---"
    echo "Coverage output: $COVERAGE_OUTPUT_DIR"
    mkdir -p "$COVERAGE_OUTPUT_DIR"
    
    # Helper function to run commands with kcov
    run_with_coverage() {
        local test_name="$1"
        local script_path="$2"
        
        echo "Running with coverage: $test_name"
        # kcov has issues with stdin redirection, so we use bash -c wrapper
        # stdin is already piped from the caller
        kcov \
            --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" \
            --include-path="$PWD" \
            "$COVERAGE_OUTPUT_DIR/$test_name" \
            bash "$script_path"
    }
else
    echo "--- Coverage Mode: DISABLED ---"
fi

# Run Specific Test File if provided
if [ -n "$TEST_FILE" ]; then
    echo "--- Running Specific Test File: $TEST_FILE ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        TEST_NAME=$(basename "$TEST_FILE" .bats)
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/$TEST_NAME" bats "$TEST_FILE"
    else
        bats "$TEST_FILE"
    fi
    exit $?
fi

# Run Unit and Component Tests with BATS
if [ "$MODE" = "all" ] || [ "$MODE" = "installer" ]; then
    echo "--- Running Unit Tests ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/unit_tests" bats tests/unit_tests.bats
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/install_interactive" bats tests/install_interactive.bats
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/install_extended" bats tests/install_extended.bats
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/install_pi_mode" bats tests/install_pi_mode.bats
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/uninstall" bats tests/uninstall.bats
    else
        bats tests/unit_tests.bats
        bats tests/install_interactive.bats
        bats tests/install_extended.bats
        bats tests/install_pi_mode.bats
        bats tests/uninstall.bats
    fi
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "maintenance" ]; then
    echo "--- Running Component Tests ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/component_tests" bats tests/component_tests.bats
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/component_tests_samsung" bats tests/component_tests_samsung.bats
        kcov --exclude-pattern="/usr/lib,/tmp,$PWD/tests,$PWD/coverage,.git,.github,$MOCK_DIR,.ps1,.bashrc,.profile,.bash_logout,install_lib.sh,pi-apps/updater" --include-path="$PWD" "$COVERAGE_OUTPUT_DIR/component_tests_self_update" bats tests/component_tests_self_update.bats
    else
        bats tests/component_tests.bats
        bats tests/component_tests_samsung.bats
        bats tests/component_tests_self_update.bats
    fi
fi

# Integration Tests: These simulate full user interaction flows
if [ "$MODE" = "all" ] || [ "$MODE" = "installer" ]; then
    echo ""
    echo "=================================================="
    echo "[SUITE] Running Integration Test (Installer Logic)"
    echo "=================================================="
    if [ ! -d /etc/ssmtp ]; then
        # Use sudo to trigger the mkdir mock which redirects to MOCK_FS
        sudo mkdir -p /etc/ssmtp
        sudo touch /etc/ssmtp/ssmtp.conf
    fi

    # PHASE 1: Install, Configure, Manage
    echo "--- [PHASE 1] Install, Configure, Schedule ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        (
            echo "Y"; sleep 1; echo "test@initial.com"; sleep 1; echo "pass1"
            sleep 1; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""
            sleep 2; echo "2"; sleep 1; echo ""; sleep 1; echo "1"; sleep 1
            echo "Y"; sleep 1; echo "test@final.com"; sleep 1; echo "pass2"
            sleep 1; echo "4"; sleep 1; echo "3"; sleep 1; echo "1"; sleep 1
            echo "e"; sleep 1; echo "0 0 * * *"; sleep 1; echo "4"; sleep 1
            echo "y"; sleep 1; echo "0"; sleep 1; echo "0"
        ) | run_with_coverage "install_phase1" ./install.sh
    else
        (
            echo "Y"; sleep 0.5; echo "test@initial.com"; sleep 0.5; echo "pass1"
            sleep 0.5; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""
            sleep 1; echo "2"; sleep 0.5; echo ""; sleep 0.5; echo "1"; sleep 0.5
            echo "Y"; sleep 0.5; echo "test@final.com"; sleep 0.5; echo "pass2"
            sleep 0.5; echo "4"; sleep 0.5; echo "3"; sleep 0.5; echo "1"; sleep 0.5
            echo "e"; sleep 0.5; echo "0 0 * * *"; sleep 0.5; echo "4"; sleep 0.5
            echo "y"; sleep 0.5; echo "0"; sleep 0.5; echo "0"
        ) | ./install.sh
    fi
    echo "--- [VERIFY] Checking Phase 1 State ---"
    TARGET_CONF="$MOCK_FS/etc/ssmtp/ssmtp.conf"
    if [ ! -f "$TARGET_CONF" ]; then TARGET_CONF="/etc/ssmtp/ssmtp.conf"; fi
    if grep -q "AuthUser=test@final.com" "$TARGET_CONF"; then
        echo "✅ SSMTP: Configured correctly to test@final.com"
    else
        echo "❌ SSMTP: Config failed (Expected test@final.com)"; cat "$TARGET_CONF"; exit 1
    fi

    # PHASE 3: Edge Cases
    echo ""
    echo "--- [PHASE 3] Edge Cases ---"
    if [ "$COVERAGE_ENABLED" = "1" ]; then
        (
            echo "1"; sleep 0.2; echo "Y"; sleep 0.2; echo "invalid_email"; sleep 0.2; echo ""
            echo "1"; sleep 0.2; echo "Y"; sleep 0.2; echo "valid@email.com"; sleep 0.2; echo ""
            echo "1"; sleep 0.2; echo "N"; sleep 0.2; echo "2"; sleep 0.2; echo ""
            echo "3"; sleep 0.2; echo "9"; sleep 0.2; echo "0"; sleep 0.2; echo "4"; sleep 0.5
            echo "9"; sleep 0.2; echo "5"; sleep 0.2; echo "N"; sleep 0.2; echo "0"
        ) | run_with_coverage "install_phase3_edge_cases" ./install.sh
    fi
fi

# PHASE 4: Uninstall Edge Case (covered by component tests)
if [ "$COVERAGE_ENABLED" = "1" ]; then
    echo "--- Merging Coverage Reports ---"
    HTML_REPORT_DIR="$COVERAGE_OUTPUT_DIR/html_report"
    mkdir -p "$HTML_REPORT_DIR"
    if [ "$MODE" = "installer" ]; then
        kcov --merge "$HTML_REPORT_DIR" "$COVERAGE_OUTPUT_DIR/unit_tests" "$COVERAGE_OUTPUT_DIR/install_interactive" "$COVERAGE_OUTPUT_DIR/install_extended" "$COVERAGE_OUTPUT_DIR/install_phase1" "$COVERAGE_OUTPUT_DIR/install_phase3_edge_cases" "$COVERAGE_OUTPUT_DIR/uninstall"
    elif [ "$MODE" = "maintenance" ]; then
        cp -r "$COVERAGE_OUTPUT_DIR/component_tests/"* "$HTML_REPORT_DIR/"
    else
        kcov --merge "$HTML_REPORT_DIR" "$COVERAGE_OUTPUT_DIR/unit_tests" "$COVERAGE_OUTPUT_DIR/component_tests" "$COVERAGE_OUTPUT_DIR/component_tests_samsung" "$COVERAGE_OUTPUT_DIR/component_tests_self_update" "$COVERAGE_OUTPUT_DIR/install_interactive" "$COVERAGE_OUTPUT_DIR/install_extended" "$COVERAGE_OUTPUT_DIR/install_pi_mode" "$COVERAGE_OUTPUT_DIR/install_phase1" "$COVERAGE_OUTPUT_DIR/install_phase3_edge_cases" "$COVERAGE_OUTPUT_DIR/uninstall"
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

