#!/bin/bash
set -e

# ==========================================
# Linting (ShellCheck)
# ==========================================
echo "--- Linting Checks ---"

if command -v shellcheck > /dev/null; then
    echo "Running ShellCheck on scripts..."
    # Check main scripts and test scripts
    # Using glob patterns to catch all relevant shell scripts
    if shellcheck install.sh scripts/*.sh tests/*.sh; then
        echo "✅ ShellCheck: All scripts passed"
    else
        echo "❌ ShellCheck: Issues found. Please fix them."
        exit 1
    fi
else
    echo "⚠️  ShellCheck not found in PATH. Skipping linting."
    echo "   (Install with: sudo apt install shellcheck or brew install shellcheck)"
    # We exit 0 here because in some dev environments it might be missing,
    # but in CI strict mode this script should be run in an environment that has it.
    # If the user intentionally runs this script, they likely want to know it's missing,
    # so the warning is crucial.
fi
