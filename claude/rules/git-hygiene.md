# Git hygiene

- Never `git add -A` or `git add .` — stage explicit paths so unrelated or generated files never ride along.
- Before any commit, verify no secrets, tokens, or `.env` files are staged (`git diff --cached --name-only` plus a look at anything suspicious).
- No `Claude-Session:` or similar tracking trailers in commit messages.
- No Claude/AI attribution in PR titles or descriptions.
A `Co-Authored-By` line in commits is the maximum, and only where settings allow it.
- When the user reports a PR merged: `git checkout main && git pull`, delete the local branch, and continue the next queued item without being asked.
- Push the branch and let the user open the PR themselves, unless the project's CLAUDE.md or memory explicitly allows creating PRs.
- Never force-push or rewrite published history unless explicitly asked.
- Keep commits small and scoped; one logical change per commit so any regression is attributable and revertable.

## Enforcement

- A `PreToolUse` hook (`scripts/safety-guard-hook.sh`, wired per-profile in `settings.json`) hard-denies `git add -A|--all|.`, `sudo`, `chmod/chown 777`, and `rm -rf` on `/`, `~`, `$HOME`, `.git`; asks before any recursive `rm`, force-push, `reset --hard`, or `clean -f`; and denies `Edit|Write` to `.env*` (except `.env.example`-style templates), `.git/`, `node_modules/`.
  Every decision is logged to `$CLAUDE_CONFIG_DIR/safety-guard.log`.
- The hook is the backstop, not the rule: an `ask` means the user decides, and a `deny` means find another way — do not work around it with `sh -c`, `eval`, or a script file.
