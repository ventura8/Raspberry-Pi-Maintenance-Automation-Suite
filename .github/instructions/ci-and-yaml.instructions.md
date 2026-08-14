______________________________________________________________________

## applyTo: "\*\*/\*.{yml,yaml}" description: "GitHub Actions and YAML reliability rules."

# CI and YAML Instructions

1. Quote shell variables in `run:` steps; use `set -euo pipefail` in multi-line scripts.
1. Keep workflow matrix distros synced with `scripts/run_docker_matrix.sh` and `AGENTS.md`.
1. Prefer pinned action versions already used in-repo; Dependabot may bump them.
1. Do not weaken or skip lint/coverage/matrix gates.
1. Upload useful logs/artifacts on failure (`reports/distro-logs/`, coverage).
1. Pass `yamllint` and `actionlint` via Docker/host lint gates.
1. Line length ≤ 140 for YAML.
1. Workflow jobs must invoke `./scripts/build-and-test.sh` stage flags only
   (`--lints-only`, `--coverage-only`, `--distro <image>`), matching local
   `./scripts/build-and-test.sh --full`. Do not call raw `lint-in-docker.sh` /
   `run_docker_matrix.sh` or ad-hoc `chmod` lists from the workflow — executable prep is
   `scripts/ensure_exec.sh` inside the entrypoint.
1. Distro/coverage containers must use host-UID bind-mount parity (`CI_UID`/`CI_GID` image
   build args + `docker run --user $(id -u):$(id -g)` via `run_docker_matrix.sh`).
