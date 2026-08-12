______________________________________________________________________

## description: "Run coverage/complexity gates and report results. Optional focus: {{FOCUS_AREA}}."

# Test & Coverage Gate

Focus (optional): {{FOCUS_AREA}}

Follow `.github/skills/test-and-coverage-gate` and `.agents/skills/test-runner`.

Prefer:

```bash
./scripts/build-and-test.sh --coverage-only
```

Report overall/per-file coverage, complexity, failures, and whether `assets/coverage.svg` needs commit.
