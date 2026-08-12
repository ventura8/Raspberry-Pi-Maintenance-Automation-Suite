______________________________________________________________________

## name: triage-issue-and-scope description: Scope bugs/features before coding — map impact across install UI, scripts, libs, tests, matrix, and docs.

# Triage Issue and Scope

## Goal

Produce a concrete implementation plan with acceptance criteria before editing code.

## Inputs

1. User request / issue text
1. Relevant paths under `install.sh`, `uninstall.sh`, `scripts/`, `lib/`, `tests/`, CI/Docker, docs
1. [`AGENTS.md`](../../../AGENTS.md) always-on policy (quality gates, installer UI, Pi vs non-Pi, VERSION SSOT)
1. Affected agent surfaces: `.agents/skills/**`, `.github/{agents,skills,prompts,instructions}`, `.github/copilot-instructions.md`
1. Package/mail portability (`lib/os_pkg.sh`, `lib/mail_send.sh`) and temp-file / TOCTOU safety (`mktemp`, mode 600)
1. Release surfaces when versioning: root `VERSION`, `docs/releases/vX.Y.Z.md`, prepare-release / release-readiness

## Procedure

1. Restate the problem and desired outcome.
1. Classify domain: installer/UI, maintenance script, pkg/mail lib, self-update, Samsung, CI/matrix, docs/agents, release.
1. List files likely to change and tests to add/update.
1. Call out invariants at risk, including:
   - cron-safe `--update`; whiptail default + text fallback; User Cancel ≠ text fallback
   - Pi/non-Pi skips; stable LVFS only for Samsung
   - VERSION SSOT (`VERSION` → `.version`); curl fail-on-HTTP for downloads
   - pkg/mail portability (apt/dnf/pacman; ssmtp or msmtp)
   - mktemp + restrictive modes for cron/mail/temp paths (no predictable `/tmp` secrets)
   - required markdown/agent sync in the **same** change set
1. Avoid destructive operations unless the user explicitly requested them.
1. Propose validation commands (host vs Docker full).
1. Recommend which `.agents/skills/*` to follow next.

## Output

1. Summary (2–4 bullets)
1. Impacted surfaces (code, tests, docs, agents)
1. Acceptance criteria checklist
1. Suggested skill sequence
1. Open questions (only if blocking)
