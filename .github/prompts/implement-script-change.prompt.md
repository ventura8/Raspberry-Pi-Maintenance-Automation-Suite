______________________________________________________________________

## description: "Implement a Bash behavior change with tests. Replace {{REQUEST_DETAILS}} with the change request."

# Implement: {{REQUEST_DETAILS}}

Follow `.github/skills/implement-script-change` and relevant `.agents/skills/*`.

Requirements:

1. Minimal scoped diff
1. Preserve cron-safe `install.sh --update`
1. Update BATS/mocks
1. No lint suppressions
1. Validate with format + lint + suite (prefer `./scripts/build-and-test.sh --full`)

Deliver: summary of code/test/docs/agent updates and commands run.
