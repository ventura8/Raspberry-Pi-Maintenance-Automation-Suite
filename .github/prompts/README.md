# Prompt Pack

Slash-style prompt templates for recurring workflows. Prefer pairing each prompt with the matching
skill under `.github/skills/` or `.agents/skills/`.

## Always-on rules

Read [`AGENTS.md`](../../AGENTS.md) first for project invariants.

## Included prompts

| Prompt | Skill |
| -------------------------------------- | ---------------------------------------------------------------------- |
| `triage-issue-and-scope.prompt.md` | `.github/skills/triage-issue-and-scope` |
| `implement-script-change.prompt.md` | `.github/skills/implement-script-change` |
| `test-and-coverage-gate.prompt.md` | `.github/skills/test-and-coverage-gate` + `.agents/skills/test-runner` |
| `ci-lint-hardening.prompt.md` | `.github/skills/ci-lint-hardening` + `.agents/skills/code-linter` |
| `release-readiness.prompt.md` | `.github/skills/release-readiness` |
| `prepare-release.prompt.md` | `.agents/skills/prepare-release` |
| `docs-sync-and-policy-check.prompt.md` | `.github/skills/docs-sync-and-policy-check` |
| `installer-tester.prompt.md` | `.agents/skills/installer-tester` |
| `distro-matrix-tester.prompt.md` | `.agents/skills/distro-matrix-tester` |

## Agents

| Agent | Use |
| ---------------------------------------- | ---------------------- |
| `.github/agents/implementation.agent.md` | General implementation |
| `.github/agents/installer-ui.agent.md` | Installer/whiptail UI |
| `.github/agents/ci-matrix.agent.md` | Docker matrix / CI |
| `.github/agents/strict-review.agent.md` | Read-only review |

## Usage

1. Open Chat (VS Code / Copilot / Cursor).
1. Start from a prompt under `.github/prompts/`.
1. Replace placeholders like `{{REQUEST_DETAILS}}`.
1. Follow linked skills; validate with `./scripts/build-and-test.sh --full` when possible.
