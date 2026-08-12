______________________________________________________________________

## name: code-linter description: Format and lint this Bash suite with autofix-first policy; prefer Docker lint image, never suppress findings.

# Code Linter Skill

Use for shell/YAML/Dockerfile/Markdown lint and format work in this repository.

## Hard rules

1. Never add `# shellcheck disable`, formatter ignores, yamllint disables, hadolint ignores, or lower thresholds.
1. Autofix first (`./tests/format.sh` / Docker lint autofix paths), then hand-fix remaining failures.
1. Line length ≤ **140** for shell, YAML, Dockerfiles. Markdown has no max-line constraint.
1. Prefer Docker lint parity: `./scripts/lint-in-docker.sh` or `./scripts/build-and-test.sh --lints-only`.

## Workflow

1. Ensure scripts are executable: `chmod +x scripts/*.sh tests/*.sh lib/*.sh install.sh uninstall.sh`.
1. Run formatters:

```bash
./tests/format.sh
```

1. Run strict host lint (quick):

```bash
STRICT_MODE=true ./tests/lint.sh
```

1. Run Docker lint (CI parity). Enable `pipefail` so a lint failure is not masked by `tee`:

```bash
set -o pipefail
mkdir -p reports/distro-logs
./scripts/lint-in-docker.sh 2>&1 | tee reports/distro-logs/lint-docker.log
```

1. Fix root causes until exit 0 with 0 errors / 0 warnings.
1. Re-run the same gate after each fix batch.

## Tool coverage expected

- `bash -n` syntax
- `shellcheck`
- `shfmt`
- `yamllint`
- `actionlint`
- `hadolint`
- `mdformat --check`

## Output

Report which gate ran, remaining failures (if any), and files touched for lint-only fixes.
