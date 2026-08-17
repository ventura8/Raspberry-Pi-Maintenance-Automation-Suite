______________________________________________________________________

## name: pipeline-runner description: Run full local CI parity via build-and-test.sh and keep fixing until all gates are green.

# Pipeline Runner Skill

Use before declaring a change done. Matches GitHub Actions locally.

## Hard rules

1. Keep fixing until `./scripts/build-and-test.sh --full` exits 0.
1. Never suppress lint/test/coverage failures or lower gates.
1. Tee long runs to `reports/distro-logs/` for live + inspectable logs.
1. After iterating on a single stage, re-run `--full` before claiming success.
1. Ensure new `*.sh` are **git-tracked** before declaring lint green
   (`tests/lint.sh` uses `git ls-files`; untracked local scripts hide CI shellcheck failures).
1. Do not ignore `scripts/coverage/` via broad `coverage/` patterns — use root-anchored
   `/coverage/` in `.gitignore` and `.dockerignore`.
1. GitHub Actions must call `./scripts/build-and-test.sh` stage flags only (`--lints-only`,
   `--coverage-only`, `--distro <image>`) — same entrypoint as local; do not invent workflow-only
   chmod/script paths.
1. Executable prep is [`scripts/ensure_exec.sh`](../../scripts/ensure_exec.sh) (host before
   bind-mount + in-container assert) so Actions UID mismatch does not false-fail coverage.
1. Test containers must run as host UID/GID (`--user $(id -u):$(id -g)`) and images must be
   built with matching `CI_UID`/`CI_GID` so bind-mount writes work on GitHub Actions.

## Full pipeline

```bash
set -euo pipefail
mkdir -p reports/distro-logs
./scripts/build-and-test.sh --full 2>&1 | tee reports/distro-logs/full-pipeline.log
```

Stages inside `--full`:

1. `./scripts/lint-in-docker.sh`
1. `./scripts/run_docker_matrix.sh --coverage-gate` (`debian:trixie`)
1. `./scripts/run_docker_matrix.sh --parallel` (compat then e2e per distro)

## Focused stages

```bash
./scripts/build-and-test.sh --lints-only
./scripts/build-and-test.sh --coverage-only
./scripts/build-and-test.sh --compat-only
./scripts/build-and-test.sh --e2e-only
./scripts/build-and-test.sh --distro debian:trixie
```

Single distro lane (equivalent to Actions matrix job):

```bash
./scripts/build-and-test.sh --distro debian:trixie
```

## Fix-until-green loop

1. Diagnose from live tee / `reports/distro-logs/*.log`.
1. Autofix formatters first (`./tests/format.sh`).
1. Fix root cause in product code or tests.
1. Re-run failed stage, then `--full`.
1. Repeat until clean.

## Gate checklist

- [ ] Docker lint clean
- [ ] Coverage ≥ 90% overall and per-file
- [ ] Complexity ≤ 15 overall and per-file
- [ ] All matrix lanes (compat + e2e) green
- [ ] Docs/agent files updated if behavior changed

## Output

Report pipeline command, stages passed, remaining failures, and files changed while fixing.
