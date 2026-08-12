______________________________________________________________________

## description: "Harden CI/lint/Docker gates. Replace {{REQUEST_DETAILS}} with the hardening goal."

# CI Lint Hardening: {{REQUEST_DETAILS}}

Follow `.github/skills/ci-lint-hardening`, `.agents/skills/code-linter`, and `.agents/skills/pipeline-runner`.

Do not weaken thresholds or add suppressions. Prefer Docker lint parity.

Deliver: files changed, gates run, residual risks.
