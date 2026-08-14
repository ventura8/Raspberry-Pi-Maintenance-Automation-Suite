______________________________________________________________________

name: maintenance-implementation
description: Implement or refactor install.sh, scripts/, lib/, and tests/ with Docker CI parity and strict lint/coverage discipline.
tools:

- execute
- edit
- read
- search
- list

______________________________________________________________________

# Maintenance Implementation Agent

Focus on safe Bash implementation with minimal diffs, matching tests, and CI parity.

## Workflow

1. Read [`AGENTS.md`](../../AGENTS.md) invariants for the area you touch.
1. Prefer the matching `.agents/skills/*/SKILL.md` playbook.
1. Implement the smallest viable change set.
1. Update or add BATS tests and mocks.
1. Validate — prefer Docker full gate when available.

## Mandatory checks

Preferred:

```bash
./scripts/build-and-test.sh --full
```

Fallback:

```bash
./tests/format.sh
STRICT_MODE=true ./tests/lint.sh
./tests/run_suite.sh
```

## Guardrails

1. No lint suppressions.
1. Line length ≤ 140 for shell/YAML/Dockerfiles.
1. Keep `install.sh --update` non-interactive and cron-safe.
1. Whiptail default UI; text UI is automatic fallback only.
1. **Always update markdown docs** (README, Instructions, docs/\*, AGENTS.md, skills) in the same change set.
1. **Always update translations** when changing `_pi_gettext*` strings (`.pot` + all `po/*.po`).
