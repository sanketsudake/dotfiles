# AGENTS.md

Global, always-on rules for the CLI coding agents that are not Claude Code:
Devin CLI reads this file at `~/.config/devin/AGENTS.md`,
GitHub Copilot CLI reads the same content at `~/.copilot/copilot-instructions.md`.
Both links come from `packages/agents/AGENTS.md` in the dotfiles repo.

Claude Code has its own file (`packages/claude/CLAUDE.md`),
because it uses `$CLAUDE_CONFIG_DIR` paths and profile-specific tooling that do not apply here.
Keep this file harness-neutral: no tool-specific paths, no slash commands.

## Skills first

Shared skills live in `~/.agents/skills/`, which both CLIs read.
Each skill is a directory with a `SKILL.md` file.
Before you start a task, check for a skill that covers it, and follow the skill instead of improvising.
Keep this file short — a rule that only applies to one kind of task belongs in a skill.

## Never publish sensitive data

These rules are absolute:

- Never commit or publish passwords, API keys, or tokens.
- Never commit a `.env` file.
- Before each commit, examine the staged files and make sure that no secret is included.

## Git hygiene

- Never run `git add -A` or `git add .`; stage each path explicitly,
so that unrelated or generated files do not go in with the change.
- Keep each commit small and limited to one logical change.
- Do not add AI attribution lines to commit messages or pull request descriptions.
- Do not force-push or rewrite published history unless the user asks for it.
- Push the branch and let the user open the pull request,
unless the project instructions permit you to open it.

## Communication

- Write in ASD-STE100 Simplified Technical English.
- Lead with the result, and keep the answer short.
- Report outcomes correctly:
if a test fails, show the output;
if you skipped a step, say so.

## Markdown style

Write all markdown with semantic line breaks (<https://sembr.org/>).
Break the line after each sentence,
and after an independent clause when this makes the structure more clear.
CommonMark renders a single newline as a space,
thus the rendered output does not change,
but each `git diff` shows one thought per line.
Do not rewrap a full paragraph only to change one sentence.
