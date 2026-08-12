______________________________________________________________________

## description: "Prepare the release for the current branch version. Optional override: {{VERSION_OVERRIDE}}."

# Prepare Release

Version override (optional): {{VERSION_OVERRIDE}}

Follow `.agents/skills/prepare-release` (and the Copilot mirror under `.github/skills/prepare-release`).

1. Read and validate root `VERSION` as the suite SSOT (`vMAJOR.MINOR.PATCH`). Use
   `VERSION_OVERRIDE` only when the user sets it explicitly (independently validate that value).
1. Update markdown + write `docs/releases/vX.Y.Z.md` for the GitHub Release body.
1. Prepare release metadata **without** amending by default. Rewrite HEAD only when the user
   explicitly confirms amend immediately beforehand (skill invocation alone is not authorization).
1. Report remaining tag/push/`gh release create` steps (do not push unless asked).
