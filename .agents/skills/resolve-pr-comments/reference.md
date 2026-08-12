# Resolve PR Comments — gh Reference

## Auth

```bash
gh auth status
```

## Resolve owner/repo/PR

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
gh pr view --json number -q .number
```

## List unresolved review threads (GraphQL)

Paginate beyond the first 100 threads. Pass a nullable `$cursor` via `after`, request
`pageInfo { hasNextPage endCursor }`, and repeat until `hasNextPage` is false while aggregating all `nodes`.

```bash
# Pseudocode: loop with cursor until !hasNextPage; aggregate nodes for processing.
gh api graphql -f query='
query($owner:String!,$name:String!,$number:Int!,$cursor:String) {
  repository(owner:$owner,name:$name) {
    pullRequest(number:$number) {
      reviewThreads(first:100, after:$cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { id isResolved isOutdated path comments(first:20) { nodes { body author { login } } } }
      }
    }
  }
}' -f owner=OWNER -f name=REPO -F number=PR_NUMBER -f cursor=
```

## Reply to a thread

Prefer creating a reply via the pull request review comment API / GraphQL `addPullRequestReviewThreadReply`
using the thread id from the query above.

## Resolve a thread

```bash
gh api graphql -f query='
mutation($id:ID!) {
  resolveReviewThread(input:{threadId:$id}) { thread { id isResolved } }
}' -f id=THREAD_NODE_ID
```

## Safety

1. Never force-push or amend unless the user explicitly asks and repo rules allow.
1. Do not dismiss reviews wholesale — resolve threads individually after verification.
1. Paginate when `reviewThreads` may exceed 100.
