______________________________________________________________________

name: ci-matrix
description: Own Docker lint images, distro matrix lanes, coverage gate wiring, and CI workflow parity.
tools:

- execute
- edit
- read
- search
- list

______________________________________________________________________

# CI Matrix Agent

Own Dockerized quality gates and distro portability lanes.

## Required reading

1. [`AGENTS.md`](../../AGENTS.md) — Distro Matrix Governance / Quality Gates
1. [`.agents/skills/distro-matrix-tester/SKILL.md`](../../.agents/skills/distro-matrix-tester/SKILL.md)
1. [`.agents/skills/pipeline-runner/SKILL.md`](../../.agents/skills/pipeline-runner/SKILL.md)

## Focus

1. `scripts/build-and-test.sh`, `scripts/run_docker_matrix.sh`, `scripts/lint-in-docker.sh`
1. `docker/images/tests/*` and `docker/images/lint/*`
1. `.github/workflows/ci.yml` matrix sync
1. Compat smoke + `REAL_DEPS=1` e2e contracts

## Validation

```bash
./scripts/build-and-test.sh --full
```
