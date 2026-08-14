______________________________________________________________________

## name: review-with-coderabbit description: User-gated CodeRabbit CLI review or findings-fix loop for this repository. Do not invoke unless the user asks. disable-model-invocation: true

# Review with CodeRabbit Skill

User-gated only. Use when the user explicitly asks for a CodeRabbit review or to fix CodeRabbit findings.

## Modes

| Mode | When |
| ------------ | ------------------------------------------------------------------------ |
| Review | Run CodeRabbit CLI, present findings, optionally fix after confirmation |
| Findings fix | User pastes findings or points at a report — verify each, fix valid ones |

## Hard rules

1. Do **not** auto-start this skill without an explicit user request.
1. Verify every finding against current code — skip incorrect/outdated items.
1. Prefer minimal fixes; keep suite invariants (no lint suppressions, cron-safe `--update`, etc.).
1. After fixes, run relevant gates (`./tests/format.sh`, lint, targeted bats, or `--full` if broad).
1. End with a classification summary (fixed / skipped / blocked).

## Workflow

1. Confirm scope (whole PR / specific files / pasted findings).
1. Ensure CodeRabbit CLI is available and authenticated per [reference.md](reference.md).
1. Run review **or** ingest pasted findings.
1. Present findings briefly; for Findings-fix mode, verify → fix → test per item.
1. Optional second pass after substantial fixes.
1. Summarize outcomes.

## Additional resources

- [examples.md](examples.md) — trigger phrases and summary templates
- [reference.md](reference.md) — CLI install/auth/review commands
