# Development & Standards

## Environment

- **OS**: Raspberry Pi OS (Debian-based)
- **Shell**: Bash
- **Runtime**: `ssmtp`, `mailutils`
- **Testing**: `bats-core`, `kcov`

## Testing & Coverage

### **Mandatory: 90% code coverage**

```bash
# Run tests with coverage (updates badge automatically)
COVERAGE=1 ./tests/run_suite.sh

# Commit the updated badge
git add assets/coverage.svg
git commit -m "Update coverage badge"
```

The `run_suite.sh` script:
1. Runs all bats tests with kcov
2. Generates `coverage/cobertura.xml`
3. Auto-updates `assets/coverage.svg`
4. Warns if coverage < 90%

## Coding Standards

- Use `set -e` for fail-fast
- Use `DEBIAN_FRONTEND=noninteractive`
- Capture stdout/stderr to logs
- Never leave system in inconsistent state

## Documentation

- Update `README.md` for user-facing changes
- Update `Instructions.md` + `docs/` for AI/developer guidance
