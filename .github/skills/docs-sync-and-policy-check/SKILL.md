______________________________________________________________________

## name: docs-sync-and-policy-check description: Keep README, Instructions, docs/, AGENTS.md, and agent skills/prompts in sync with behavior and policy — always in the same change set.

# Docs Sync and Policy Check

## Goal

Prevent documentation and agent-config drift after behavior changes.

**Mandatory:** if you changed code, tests, CI, or policy, update the matching markdown in the
**same change set**. Shipping without docs is incomplete.

UI strings are English-only (`lib/ui_msg.sh`); do not add gettext catalogs or PO tooling.

## Sync targets

1. `README.md` — user-facing install/UI expectations
1. `Instructions.md` — AI/developer handbook
1. `docs/*.md` — overview, script logic, standards, releases
1. `AGENTS.md` — always-on agent law
1. `.agents/skills/**` — task playbooks
1. `.github/{agents,skills,prompts,instructions}/**` and `copilot-instructions.md`
1. `.agent/instructions.md`

## Procedure

1. Diff behavior changes vs docs/agent claims.
1. Update all stale references (commands, distro list, UI semantics, gates).
1. Ensure mdformat-friendly Markdown (no max line length).
1. Do not close the task while docs still lag the code.

## Output

List of files updated + remaining inconsistencies (if any).
