# Review with CodeRabbit — CLI Reference

## Install / auth

Follow current CodeRabbit CLI docs for install and `coderabbit auth` (or equivalent).
Prefer a pinned documented install path when the team standardizes one.

## Review commands (typical)

```bash
# Repository / PR scoped review — adjust flags to installed CLI version
coderabbit review
```

Prefer non-interactive flags when available. Capture output under `reports/distro-logs/` if long.

## Findings vs new review

1. **New review**: run CLI, then triage.
1. **Findings mode**: user provides comments/report; do not re-run CLI unless asked.

## Severity guidance for this repo

Treat as blocking when a finding impacts:

- Cron-safe `--update` / self-update
- Whiptail cancel vs fallback semantics
- Coverage/complexity gates
- Destructive firmware paths without mocks
- Shell injection / unquoted expansions in scripts

## Timing

Large reviews can be slow — stream output and avoid claiming completion until the CLI exits.
