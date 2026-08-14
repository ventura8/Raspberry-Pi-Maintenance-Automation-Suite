______________________________________________________________________

## description: "Pre-merge/pre-release readiness report. Optional target: {{RELEASE_TARGET}}."

# Release Readiness: {{RELEASE_TARGET}}

Follow `.github/skills/release-readiness` and `AGENTS.md` PR checklist.

1. Produce a pass/fail table for lint, coverage, complexity, matrix, installer invariants,
   docs/agent sync, and residual risks.
1. When `{{RELEASE_TARGET}}` is set, also check `docs/releases/vX.Y.Z.md` and the amended
   HEAD commit message. When no target is set (pre-merge), report those two checks as **N/A**.
