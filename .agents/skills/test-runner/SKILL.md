______________________________________________________________________

## name: test-runner description: Run BATS suites with coverage and complexity gates for the Raspberry Pi maintenance scripts.

# Test Runner Skill

Use to validate unit/component/installer/e2e tests and enforce coverage/complexity policy.

## Hard rules

1. Overall coverage ≥ **90%**; per-file coverage ≥ **90%**.
1. Overall complexity ≤ **15**; per-file complexity ≤ **15**.
1. Do not skip tests or weaken thresholds to pass.
1. Mock hardware/destructive commands; with `REAL_DEPS=1`, use real packages only.
1. Keep installer `--update` tests free of stdin-pipe assumptions.

## Preferred commands

Coverage gate (Docker, matches CI):

```bash
./scripts/build-and-test.sh --coverage-only
```

Host suite:

```bash
COVERAGE=1 ./tests/run_suite.sh
```

Installer-focused:

```bash
./tests/run_suite.sh --installer-only
```

Maintenance scripts only:

```bash
./tests/run_suite.sh --maintenance-only
```

## Mocking philosophy

1. Shared mocks: `tests/setup_mocks.sh` (`curl`, `sudo`, crontab, apt/dnf/pacman as needed, `whiptail`).
1. Isolate `INSTALL_DIR`, `SSMTP_CONF`, `REVALIASES`, `MOCK_DIR`, `TEST_MODE=true`.
1. Whiptail mock modes: exercise **success path** and **text fallback** (`whiptail_mode=fail|missing`).
1. Pi toggles: `MOCK_IS_PI=true|false` for Pi-only script visibility.
1. Never mock product scripts under test as “always succeed” — mock external tools only.

## Coverage artifacts

1. `coverage/cobertura.xml` from kcov
1. `tests/transform_coverage.py` enforces thresholds + complexity
1. Commit `assets/coverage.svg` when coverage changes

## Output

Summarize suites run, pass/fail counts, coverage %, complexity, and any flaky or host-specific issues
(for example Samsung mocks when real `fwupdmgr`/`7z` exist on the host).
