______________________________________________________________________

## name: self-update-tester description: Validate cron-safe suite self-update via GitHub release tags and install.sh --update.

# Self-Update Tester Skill

Use when changing `scripts/update_self.sh`, installer `--update`, version files, or
`tests/component_tests_self_update.bats`.

## Invariants

1. Repo SSOT is root `VERSION` (`vMAJOR.MINOR.PATCH`); GitHub tags must match it.
1. Local installed version is `$INSTALL_DIR/.version` (written from `VERSION` by `install.sh`).
1. Compare against GitHub Releases API `releases/latest`.
1. On mismatch: download **tagged** `install.sh` **and** `VERSION`, run `bash "$INSTALL_SCRIPT" --update`.
1. **Never** pipe installer on stdin for self-update (cron has no TTY; piping breaks `--update`).
1. Email reports: success, up-to-date, and failure (API/download/exec errors).
1. `install.sh --update` must only run deps + `download_scripts` — no interactive UI.

## Scenarios

1. Up-to-date → no rewrite; success/up-to-date mail
1. Newer tag → download install.sh + VERSION + `--update` + `.version` refresh
1. VERSION download failure → failure mail
1. API failure → failure mail, non-zero or handled error path per script contract
1. Download failure → failure mail
1. Cron invocation simulation: empty stdin, no `/dev/tty` reliance for `--update`

## Commands

```bash
bats tests/component_tests_self_update.bats
./tests/run_suite.sh --installer-only
```

## Mock notes

1. Mock `curl` for Releases API JSON, raw.githubusercontent.com `install.sh`, and `VERSION`.
1. Assert argv is `bash install.sh --update` without pipe.
1. Keep `RAW_URL` / `INSTALL_DIR` overridable in tests.

## Output

Confirm cron-safety, tag comparison behavior, and email/reporting outcomes for each case.
