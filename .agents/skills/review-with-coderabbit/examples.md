# Review with CodeRabbit — Examples

## Trigger phrases (user-gated)

- “Run CodeRabbit on this PR”
- “Fix the CodeRabbit findings”
- “Review with CodeRabbit and patch what’s valid”

## Classification labels

- **Valid** — confirmed bug/regression/policy break → fix
- **Style nit** — optional unless it violates repo gates (line length, shellcheck)
- **Incorrect** — contradicts tests/`AGENTS.md` → skip with evidence
- **Already fixed** — present on HEAD → skip
- **Out of scope** — unrelated to current change → skip or defer

## Final summary template

```text
CodeRabbit pass
- Findings reviewed: N
- Fixed: A
- Skipped (incorrect/already fixed/out of scope): B
- Blocked: C
Validation: <commands run>
```
