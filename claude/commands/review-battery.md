Run the full review battery on the current changes and consolidate the findings.

Scope: the working diff plus this branch's commits vs the default branch, unless `$ARGUMENTS` names a different base.
If the scoped diff is empty, say so and stop.
To review an external PR end-to-end, use `/review-pr-worktree` instead — it isolates the PR in a worktree, runs this battery, and posts the findings.

Pre-filter the diff before reviewing:

- Exclude generated and vendored content: lock files, `vendor/` dirs, minified assets, and generated code (e.g. `zz_generated*`, `pkg/generated/`, files with a generated-file header).
- Keep database migrations and security-sensitive config in scope even when they carry generation markers.

Scale the battery to the diff:

- Trivial diffs (roughly ≤10 changed lines, no security-sensitive files): run only `/code-review` and `/security-review`.
- Everything else: run the full battery.

Run these review passes in order, each via its skill/command (do not reimplement them).
Findings-only passes run first so the diff is stable; the passes that apply changes by design come last:

1. `/code-review`
2. `/security-review`
3. `/thermo-nuclear-code-quality-review`
4. `/simplify`
5. `/deslop`
6. `/make-pr-easy-to-review`

Then consolidate:

- Deduplicate findings across the passes — same file, line, and root issue is one finding; keep the most severe framing and note every pass that flagged it.
- Categorize each deduplicated finding with a kebab-case category (e.g. `correctness`, `security`, `performance`, `simplification`, `maintainability`, `test-coverage`, `style`); pick the category of the root issue, not of the pass that flagged it.
- Assign each finding a severity tier: `critical` (breaks correctness or is exploitable), `warning` (measurable risk), `suggestion` (improvement).
- Verify before reporting: for every `critical` and `warning`, re-read the cited source and actively try to refute the finding.
Drop anything speculative or theoretical, already handled elsewhere in the code, or anchored on lines this branch did not change.
Security findings must describe a concrete exploit path — real injection, secret, or authorization issues, not defense-in-depth wishes.
- Present one list grouped by category and ranked by severity within each group, each entry with `file:line`, its severity, and a one-sentence issue statement.
- End with an overall verdict, biased toward approval: `warning`s and `suggestion`s alone mean merge-ready with comments; only a surviving `critical` means needs changes.
- Do not apply fixes beyond what the individual passes already applied by design (e.g. `/simplify` applies its cleanups); for everything else, wait for the user to pick which findings to fix.
