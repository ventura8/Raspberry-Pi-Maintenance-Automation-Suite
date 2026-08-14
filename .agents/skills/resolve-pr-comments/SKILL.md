______________________________________________________________________

## name: resolve-pr-comments description: Resolve every open GitHub PR review thread with gh — verify, fix or skip, reply, then resolve.

# Resolve PR Comments Skill

Use when asked to address PR review comments (Bugbot, CodeRabbit, humans, etc.).

## Hard rules

1. Process **every** unresolved review thread — no silent drops.
1. Verify each comment against the code before changing anything.
1. Prefer minimal fixes that satisfy the finding without drive-by refactors.
1. Reply on the thread before resolving.
1. Never resolve a thread that is still incorrect/unfixed.
1. Do not use `gh` interactively; scriptable commands only.

## Workflow

1. Ensure `gh` is authenticated (`gh auth status`).
1. Identify PR number (argument, current branch, or `gh pr view`).
1. List unresolved review threads (GraphQL `reviewThreads`).
1. For each thread:
   - Read comment + code location.
   - Classify: **valid** / **already fixed** / **incorrect** / **out of scope**.
   - If valid: implement fix + tests as needed; run relevant gates.
   - Reply with what changed or why skipped.
   - Resolve thread when done.
1. Confirm zero unresolved threads remain.
1. Summarize: fixed / skipped / blocked.

## Reply shapes

- Valid + fixed: what changed + why it addresses the comment.
- Skipped (incorrect): brief evidence from code.
- Skipped (out of scope): why + suggested follow-up if useful.
- Blocked: what is needed from the author/reviewer.

## Additional resources

- See [examples.md](examples.md) for reply templates.
- See [reference.md](reference.md) for `gh` GraphQL/REST snippets.
