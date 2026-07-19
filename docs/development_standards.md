# Development & Standards

## Environment

- **OS**: Raspberry Pi OS (Debian-based)
- **Shell**: Bash
- **Runtime**: `ssmtp`, `mailutils`
- **Testing**: `bats-core`, `kcov`

## Testing & Coverage

### **Mandatory: 90% code coverage (overall and per-file in CI)**

```bash
# Run tests with coverage (updates badge automatically)
COVERAGE=1 ./tests/run_suite.sh

# Commit the updated badge
git add assets/coverage.svg
git commit -m "Update coverage badge"
```

The `run_suite.sh` script:

1. Runs all bats tests with kcov
1. Generates `coverage/cobertura.xml`
1. Auto-updates `assets/coverage.svg`
1. Warns if coverage < 90%

CI validation enforces both coverage and complexity gates:

1. Overall merged coverage >= 90%
1. Per-file coverage >= 90% for each covered script file
1. Overall complexity \<= 15
1. Per-file complexity \<= 15

## Coding Standards

- Use `set -e` for fail-fast
- Use `DEBIAN_FRONTEND=noninteractive`
- Capture stdout/stderr to logs
- Never leave system in inconsistent state
- Meet complexity thresholds through logic refactoring, not by removing useful comments.

## Linting & Formatting Standards

The project enforces a multi-layer lint gate:

1. `shellcheck` for shell correctness and safety
1. `shfmt` for shell formatting consistency
1. `bash -n` syntax validation for all shell scripts
1. `yamllint` for YAML and workflow structure
1. `actionlint` for GitHub Actions validation
1. `hadolint` for Dockerfile best practices
1. `mdformat --check` for Markdown formatting checks
1. 140-character maximum line length enforced across shell, YAML, and Dockerfiles

Markdown lint is mandatory in CI strict mode, but markdown files do not have a max line-length requirement.

Run all checks locally:

```bash
./tests/format.sh
STRICT_MODE=true ./tests/lint.sh
./tests/run_suite.sh
```

## Documentation

- Update `README.md` for user-facing changes
- Update `Instructions.md` + `docs/` for AI/developer guidance
- Add or update release description markdown in `docs/release/` when preparing a tagged release or amendable release commit
