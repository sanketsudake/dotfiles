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
