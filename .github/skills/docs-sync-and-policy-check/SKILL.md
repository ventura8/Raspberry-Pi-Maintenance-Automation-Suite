______________________________________________________________________

## name: docs-sync-and-policy-check description: Keep README, Instructions, docs/, AGENTS.md, and agent skills/prompts in sync with behavior and policy — always in the same change set.

# Docs Sync and Policy Check

## Goal

Prevent documentation and agent-config drift after behavior changes.

**Mandatory:** if you changed code, tests, CI, or policy, update the matching markdown in the
**same change set**. Shipping without docs is incomplete.

If you changed marked gettext strings (`_pi_gettext*`), also update `po/pi-maintenance-suite.pot`
and **every** `po/*.po` in `po/SUPPORTED_LANGUAGES` in the same change set (no empty/fuzzy/
English-copied non-`en` msgstr). Run `scripts/i18n/extract_pot.sh` → `sync_pos.sh` → fill →
`check_catalog_quality.py`.

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
