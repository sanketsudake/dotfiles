Run the full review battery on the current changes and consolidate the findings.

Scope: the working diff plus this branch's commits vs the default branch, unless `$ARGUMENTS` names a different base or a PR number.

Run these review passes in order, each via its skill/command (do not reimplement them):

1. `/code-review`
2. `/security-review`
3. `/simplify`
4. `/thermo-nuclear-code-quality-review`
5. `/deslop`
6. `/make-pr-easy-to-review`

Then consolidate:

- Deduplicate findings across the six passes — same file, line, and root issue is one finding; keep the most severe framing and note every pass that flagged it.
- Categorize each deduplicated finding with a kebab-case category (e.g. `correctness`, `security`, `performance`, `simplification`, `maintainability`, `test-coverage`, `style`); pick the category of the root issue, not of the pass that flagged it.
- Present one list grouped by category and ranked by severity within each group, each entry with `file:line` and a one-sentence issue statement.
- Do not apply fixes beyond what the individual passes already applied by design (e.g. `/simplify` applies its cleanups); for everything else, wait for the user to pick which findings to fix.
