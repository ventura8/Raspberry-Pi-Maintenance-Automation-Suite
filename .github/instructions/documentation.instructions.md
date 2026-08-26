______________________________________________________________________

## applyTo: "\*\*/\*.md" description: "Markdown documentation accuracy and mandatory same-change-set sync rules."

# Documentation Instructions

1. **Always update markdown when you change code/tests/CI** — same change set, never deferred.
1. Keep user docs accurate for install one-liner, whiptail UI, and text fallback.
1. When behavior/policy changes, update README, Instructions.md, docs/\*\*/\*, **and** AGENTS.md / `.agents/skills/**`, `.github/{agents,skills,prompts,instructions}`, and `.github/copilot-instructions.md` as needed.
1. Markdown has no max-line constraint; still keep mdformat-clean structure.
1. Do not invent OS/hardware support — align distro matrix wording with `AGENTS.md`.
1. Release notes belong under `docs/releases/vX.Y.Z.md` (GitHub Release body; use `prepare-release` skill). Push the matching tag only after the release commit is merged into the default branch; `release.yml` publishes that file (and requires the tag commit to be an ancestor of the default branch).
