______________________________________________________________________

## name: ci-lint-hardening description: Harden CI lint tooling, Docker lint image, workflows, and matrix wiring without weakening gates.

# CI Lint Hardening

## Goal

Improve lint/CI reliability while keeping strict no-suppression policy.

## Procedure

1. Prefer changes that keep host `tests/lint.sh` and Docker `scripts/lint-in-docker.sh` aligned.
1. Update `docker/images/lint/**` when tool versions or packages change.
1. Keep `.github/workflows/ci.yml` quoting-safe and action-pinned.
1. Run `actionlint` / `yamllint` / `hadolint` via existing gates.
1. Do not skip steps or lower thresholds to greenwash CI.

## Companion skills

- [`.agents/skills/code-linter/SKILL.md`](../../../.agents/skills/code-linter/SKILL.md)
- [`.agents/skills/pipeline-runner/SKILL.md`](../../../.agents/skills/pipeline-runner/SKILL.md)

## Validation

```bash
./scripts/lint-in-docker.sh
./scripts/build-and-test.sh --lints-only
```
