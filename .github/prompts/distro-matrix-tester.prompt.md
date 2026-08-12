______________________________________________________________________

## description: "Run distro matrix / Docker lane validation. Optional distro: {{DISTRO}}."

# Distro Matrix: {{DISTRO}}

Follow `.agents/skills/distro-matrix-tester`.

If {{DISTRO}} is set, run that lane; otherwise run parallel matrix. Keep CI/Dockerfile/docs in sync if lanes change.

Deliver: lane results + sync status.
