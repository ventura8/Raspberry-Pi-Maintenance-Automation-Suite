______________________________________________________________________

## name: samsung-firmware-tester description: Validate Samsung NVMe firmware update script paths (fwupdmgr first, scrape/ISO fallback) with safe mocks.

# Samsung Firmware Tester Skill

Use when changing `scripts/update_samsung_ssd.sh`, related mocks, or `tests/component_tests_samsung.bats`.

## Invariants

1. **Primary**: `fwupdmgr` / LVFS **stable** channel only — never enable `lvfs-testing`.
1. **Fallback**: scrape Samsung support tools page → download ISO → extract `fumagician` → apply.
1. Never flash real devices in CI or agent runs.
1. Mock `fwupdmgr`, `nvme`, network fetch, and extraction tools in unit/component tests.
1. With `REAL_DEPS=1`, packages may be real; hardware/destructive commands stay mocked.

## Scenarios to cover

1. LVFS update available → success path
1. LVFS no device / no update → fallback scrape path
1. Scrape/parse failure → clear failure email/log
1. Missing tools (`nvme-cli`, `p7zip`/`7zip`, `cpio`) → install via `lib/os_pkg.sh` mappings
1. Non-Samsung NVMe → skip safely

## Commands

```bash
bats tests/component_tests_samsung.bats
# or broader
./tests/run_suite.sh --maintenance-only
```

## Mock pitfalls

1. Hosts with real `/usr/bin/fwupdmgr` or `7z` can bypass weak mocks — prefer PATH-prefixed mocks
   from `tests/setup_mocks.sh` and avoid falling through to system binaries.
1. `lib/os_pkg.sh` seeds a cron-friendly PATH only when `MOCK_DIR` is unset; with `MOCK_DIR` set it
   must not re-append `/usr/bin` (Fedora ships real `7z`, which would defeat `path_hiding_cmds`).
1. Keep isolation under `/tmp/mocks` and temp ISO paths (`mktemp`, not fixed `/tmp/samsung_fw.iso`).

## Output

Describe which primary/fallback branches were exercised and confirm no live flash risk.
