______________________________________________________________________

## description: Run and report full quality gate results, including tests, coverage posture, and failure triage.

Execute the quality gate for current changes and provide a merge-readiness report.

Run flow:

1. Identify changed files and impacted test areas.
1. Run targeted tests first.
1. Run full suite.
1. If requested, run coverage mode and summarize coverage posture.

Required report format:

1. Overall status: PASS or FAIL.
1. Targeted test results.
1. Full suite results.
1. Coverage status against >= 90% expectation.
1. Failures with root-cause hypotheses.
1. Next fixes in priority order.

Constraints:

- Do not hide failures.
- Keep output concise but actionable.
