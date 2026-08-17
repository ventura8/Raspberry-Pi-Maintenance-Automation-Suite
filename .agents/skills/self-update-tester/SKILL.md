______________________________________________________________________

## name: self-update-tester description: Validate cron-safe suite self-update via GitHub release tags and install.sh --update.

# Self-Update Tester Skill

Use when changing `scripts/update_self.sh`, installer `--update`, version files, or `tests/component_tests_self_update.bats`.

## Invariants

1. Repo SSOT is root `VERSION` (`vMAJOR.MINOR.PATCH`); GitHub tags must match it.
1. Local installed version is `$INSTALL_DIR/.version` (written from `VERSION` by `install.sh`).
1. Compare against GitHub Releases API `releases/latest`.
1. On mismatch: stage tagged `install.sh`, `VERSION`, and `lib/` in a `mktemp` dir, export `RAW_URL`, run `bash "$stage/install.sh" --update`. Do **not** write `$INSTALL_DIR/../install.sh`. Abort if `mktemp` fails or staged `VERSION` does not match the release tag.
1. **Never** pipe installer on stdin for self-update (cron has no TTY; piping breaks `--update`).
1. Email reports: success, up-to-date, and failure (API/download/exec errors).
1. `install.sh --update` runs deps + `download_scripts` + `quiet_suite_cron_jobs`; no interactive UI.
1. `--update` sources `$INSTALL_DIR/lib` when the installer has no sibling `lib/`; fail closed if package helpers are missing.
1. `download_scripts` replaces files via `mktemp` + `mv` under the destination directory (same-filesystem atomic replace).
1. Optional lib fetches in `stage_release_tree` curl to a temp file and `mv` only on success (no partial `$dest/lib/*.sh`).
1. `download_scripts` rewrites `RECIPIENT_EMAIL="..."` to the configured mail user so `--update` cannot restore a hardcoded inbox.
1. Crontab lines end with `>/dev/null 2>&1`; `quiet_suite_cron_jobs` preserves `@daily`-style macros.

## Scenarios

1. Up-to-date → no rewrite; success/up-to-date mail
1. Newer tag → stage install.sh + VERSION + lib/ + `--update` + `.version` refresh
1. VERSION download failure → failure mail
1. install.sh download failure → failure mail
1. API failure → failure mail, non-zero or handled error path per script contract
1. Download failure → failure mail
1. Cron invocation simulation: empty stdin, no `/dev/tty` reliance for `--update`
1. Tagged `RAW_URL` is exported into `--update`
1. Parent-dir `$INSTALL_DIR/../install.sh` is not required and must not be invoked

## Commands

```bash
bats tests/component_tests_self_update.bats
./tests/run_suite.sh --installer-only
```

## Mock notes

1. Mock `curl` for Releases API JSON, tagged `install.sh`, `VERSION`, and `lib/*.sh`.
1. Assert argv is `bash <staged>/install.sh --update` without pipe.
1. Keep `RAW_URL` / `INSTALL_DIR` overridable in tests.

## Output

Confirm cron-safety, tag comparison behavior, and email/reporting outcomes for each case.
