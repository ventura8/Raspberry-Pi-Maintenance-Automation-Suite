______________________________________________________________________

## description: Triage a bug or feature request and produce concrete implementation scope, impacted files, and acceptance criteria.

Analyze this request for the Raspberry Pi Maintenance Automation Suite and produce a triage plan.

Request:

- {{REQUEST_DETAILS}}

Required output:

1. Scope classification: Pi-only, non-Pi, or both.
1. Impacted files grouped by runtime scripts, tests, CI, and docs.
1. Risks and likely regressions.
1. Acceptance criteria with explicit pass/fail behavior.
1. Minimal implementation plan in ordered steps.
1. Validation commands to run before merge.

Constraints:

- Keep scope minimal and test-driven.
- Respect strict lint policy and no suppression rules.
- Preserve cron-safe and non-interactive update paths.
