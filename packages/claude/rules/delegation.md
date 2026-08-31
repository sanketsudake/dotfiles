# Delegation

When to hand work to a subagent instead of doing it inline:

- Broad multi-file searches or "how does X work across the repo" → Explore agent; keep only the conclusion in context.
- A written implementation plan, before executing it → `plan-reviewer` agent; act on its REVISE issues before starting.
- Repetitive mechanical batches where every decision is already made → `bulk-mechanic` agent (haiku); give it the exact transform and file list.
- Post-implementation PR follow-through (push, CI, bot review threads) → `pr-shepherd` agent.
- New or vendored skills before committing → `skill-auditor` agent.
- Waiting on CI after a push → the `watch-ci` skill; other long waits → the Monitor tool.
Never hand-roll `gh pr checks` + `sleep` polling loops.

Stay inline when the task is a single-file edit, needs conversation context a subagent won't have, or is faster to do than to specify.
Delegating a search means not also running it yourself; wait for the result.

## Parallel writers

- Before dispatching two or more agents that will edit the same repo at once, decide disjoint file ownership at plan time and put each agent's file list in its brief.
- If disjoint ownership cannot be guaranteed, give each agent its own worktree (`isolation: "worktree"` on the Agent call, or the `superpowers:using-git-worktrees` skill) and add an explicit merge step afterwards.
  Two agents in one checkout overwrite each other silently: A reads, B reads, A writes, B writes, and A's edit is gone with no error.
- Read-only agents (Explore, plan-reviewer, skill-auditor) may share the checkout freely.

## Verify before acting on carried state

- A fact carried from earlier in the session or recalled from memory — a file exists, a branch is at X, a step is "already applied", a skill is materialized — may have gone stale silently.
  Before acting on it, re-verify with a fresh read or command; recompute what is cheap to derive (file contents, test results, branch state) instead of trusting the remembered value.
