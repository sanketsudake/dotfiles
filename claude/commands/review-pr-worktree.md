Review the GitHub PR given in `$ARGUMENTS` (a PR number, e.g. `3606`) in an isolated worktree, then post the findings on the PR.

1. Never mutate the current checkout.
Fetch and isolate: `git fetch origin pull/<N>/head:pr-<N>`, then `git worktree add <repo-root>/../<repo>-pr-<N> pr-<N>`.
2. In the worktree, run `/review-battery` against the PR's diff vs its base branch.
3. Deduplicate the findings across passes before posting anything.
4. Post on the PR via `gh`:
   - Inline code suggestions (```suggestion blocks) wherever a concrete fix exists — prefer suggestions over plain comments.
   - Plain review comments for findings without a mechanical fix.
   - One summary comment with the overall verdict (merge-ready / needs changes / should not merge as-is).
5. Clean up: `git worktree remove --force` the worktree and delete the `pr-<N>` branch.

Do not push commits to the PR branch; this command reviews and comments only.
