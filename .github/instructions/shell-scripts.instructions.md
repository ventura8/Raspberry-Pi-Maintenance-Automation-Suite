______________________________________________________________________

## applyTo: "\*\*/\*.sh" description: "Use when editing Bash scripts in this repo; enforces safe shell patterns, lint compliance, and project behavior invariants."

# Shell Script Instructions

## Style and Safety

1. Use Bash-compatible syntax and preserve executable shebangs.
1. Quote variable expansions unless intentional word splitting is required.
1. Use explicit exit handling with meaningful error messages.
1. Keep script logic readable; extract helpers when blocks grow too large.

## Project Invariants

1. Do not break non-Pi execution paths for generic Linux systems.
1. Keep `install.sh --update` non-interactive and cron-safe.
1. Preserve update/reporting behavior unless requirement says otherwise.
1. Avoid introducing dependencies unless necessary and test-covered.

## Lint and Format

1. Changes must pass shellcheck, shfmt, and bash syntax checks.
1. Do not add shellcheck disable directives.
1. Keep line length at or below 140 characters for shell files.
