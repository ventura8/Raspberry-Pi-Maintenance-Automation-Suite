______________________________________________________________________

## applyTo: "tests/\*\*/\*.{bats,sh,py}" description: "BATS/mocks/coverage test conventions for this suite."

# Tests Instructions

1. Keep tests deterministic; isolate `INSTALL_DIR`, `SSMTP_CONF`, `REVALIASES`, `MOCK_DIR`, `TEST_MODE`.
1. Prefer shared mocks from `tests/setup_mocks.sh`; mock external tools, not product logic.
1. Cover whiptail success **and** text-fallback paths for installer changes.
1. Self-update tests must assert no stdin pipe into `install.sh --update`.
1. `REAL_DEPS=1` e2e may use real packages; still mock hardware/destructive commands.
1. Coverage ≥ 90% overall and per-file; complexity ≤ 15 overall and per-file.
1. Update drivers / `transform_coverage.py` inputs when adding newly covered scripts.
1. Avoid relying on host-installed `fwupdmgr`/`7z` leaking past mocks.
