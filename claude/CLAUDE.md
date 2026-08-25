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

### Semantic Line Breaks (SemBr)

- Write all markdown with semantic line breaks per the spec at <https://sembr.org/>.
- Always break after each sentence (`.`, `!`, `?`);
prefer a break after independent clauses (`,`, `;`, `:`, `—`);
break after dependent clauses only when it clarifies structure.
- Why: CommonMark renders single newlines as spaces,
so the rendered HTML is unchanged —
but `git diff` becomes per-thought and review is surgical.
- Applies to all markdown: blog posts, docs, READMEs, PR descriptions.
- Don't rewrap an entire paragraph just to add or reword one sentence.
- To reflow existing markdown into SemBr — one file or a whole project — invoke the `sembr-reformat` skill.
It preserves rendered output, code blocks, tables, and frontmatter.

# Interacting with browser

- My browser is **Helium** (`/Applications/Helium.app`), a Chromium fork — not Google Chrome.
It holds the live logins, so all browser work attaches to Helium.
When a skill says "the user's real Chrome", read it as Helium.
- Remote debugging comes from the toggle at `helium://inspect/#remote-debugging` —
no restart, tabs and logins survive, one consent prompt.
If it is off, ask me to enable it; do not relaunch the browser.
- That toggle serves no `/json` discovery, so `--cdp 9222` and `--auto-connect` time out.
Read the browser WebSocket URL from Helium's own `DevToolsActivePort` file and pass it explicitly:

```sh
PF="$HOME/Library/Application Support/net.imput.helium/DevToolsActivePort"
EP="ws://127.0.0.1:$(head -1 "$PF")$(sed -n 2p "$PF")"
```

- Default to `/agent-browser` for browser work; attach with `--cdp "$EP" --pin-tab`.
For a detached or headless browser, use its own named session.
- Use `/drive-chrome-cdp` (`chrome-cdp`) when a skill names it (the Workday, Engage, and Microsoft-SSO skills)
or when the task needs its primitives:
`wait --request`, cascade `select`, `fill --by cell`, `--in-row`, `grid`, `recipe`, exit-code branching.
Start the daemon first — `chrome-cdp daemon start --endpoint "$EP" --json` —
because it holds one connection, so the consent prompt is answered once per session, not on every attach.
For parallel agents on one browser, `--session <name>` namespaces the sticky current tab so they do not steal each other's tab.
- Both tools attach to my real browser and can raise one "Allow remote debugging?" consent prompt;
run one probe and wait for it, do not stack probes.
- Type no credentials in either tool; stop at a login or passkey page and ask me to sign in.
