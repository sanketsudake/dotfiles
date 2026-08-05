Always talk in ASD-STE100 Simplified Technical English.

## NEVER EVER DO

These rules are ABSOLUTE:

### NEVER Publish Sensitive Data

- NEVER publish passwords, API keys, tokens to git/npm/docker
- Before ANY commit: verify no secrets included
- Never commit `.env` to git.

## Rules

Longer-form conventions live in `$CLAUDE_CONFIG_DIR/rules/` and apply in every session:

- `model-routing.md` — which model/effort tier a task deserves (haiku mechanical, sonnet routine, session model for judgment) and how to set them on subagent/Workflow calls.
- `git-hygiene.md` — staging, commit, and push discipline (never `git add -A`; user opens PRs unless the project says otherwise).
- `delegation.md` — when to hand work to the `plan-reviewer`, `bulk-mechanic`, `pr-shepherd`, `skill-auditor`, or Explore subagents instead of doing it inline.

## Markdown Style

### One sentence per line

- Within paragraphs, put each sentence on its own line.
- Why: CommonMark renders single newlines as spaces, so the rendered HTML is unchanged — but `git diff` becomes per-sentence and review is surgical.
- Applies to all markdown: blog posts, docs, READMEs, PR descriptions.
- Don't rewrap an entire paragraph just to add or reword one sentence.
- A reusable formatter lives at `$CLAUDE_CONFIG_DIR/scripts/md-one-sentence-per-line.py` (symlinked from this repo's `claude/scripts/`).
Run it on any markdown file (or batch) to enforce this.
It preserves frontmatter, fenced code, Hugo shortcodes, tables, headings, blockquote prefixes, list markers, and HTML comments.

# Interacting with browser

Prefer /drive-chrome-cdp for interacting with my browser.  Use /agent-browser if detached browser is needed.
