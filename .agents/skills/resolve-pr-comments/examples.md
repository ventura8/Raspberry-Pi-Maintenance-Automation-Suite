# Resolve PR Comments — Examples

## Valid finding (fixed)

> Fixed in `scripts/update_self.sh`: `--update` is now invoked with an argv array (no stdin pipe),
> matching the cron-safe installer contract. Covered by `tests/component_tests_self_update.bats`.

## Already fixed

> Confirmed on current HEAD: whiptail Cancel (rc 1/255) returns to the menu and does not force
> text fallback. No further code change.

## Incorrect finding

> Skipped: `check_dependencies` already installs `whiptail` on Debian-family hosts; the warning
> path only applies when apt install fails, which intentionally falls back to the text UI.

## Out of scope

> Skipped for this PR: Pi 5 UEFI quirks are outside the installer UI change. Happy to track as a
> follow-up issue if you want.

## Final summary example

```text
PR #42 review threads
- Fixed: 4
- Skipped (incorrect/already fixed): 2
- Blocked: 0
Unresolved remaining: 0
```
