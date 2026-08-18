---
name: harvest-automation
description: >-
  Mines past Claude Code sessions for recurring patterns and turns them into
  durable automation: skills, CLAUDE.md entries, memory, and permission
  allowlists.
  Use when invoked as /harvest-automation, optionally with a window like
  "7d", or when the user asks for an end-of-session review, "what should we
  automate", "mine my recent sessions", or reports recurring manual
  workflows, repeated corrections, repeated permission prompts, or
  preferences worth capturing as a skill, CLAUDE.md entry, or memory.
  Runs only on explicit invocation, not automatically.
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Harvest Automation

> Local skill (`.source.json` has `"repo": null`); replaces the old `retrospect` and `workflow-from-chats` skills.

## Core principle

Capture a pattern only if it recurs 2+ times, or the user asks to keep it — one-offs are noise.
Support each claim with evidence: a session id, a turn number, a verbatim quote (≤15 words), or a tool-call signature.

## When to use

Run only on explicit invocation.
`/harvest-automation` analyzes the current session; `/harvest-automation 7d` (or "last week") analyzes a window of recent sessions.
Decline if the user wants a plain summary, the scope has under 4 real user turns, or there were no tool calls.

## Scope and gathering

Default scope: the current session.
Reflect on the in-context conversation first.

- For a window (`Nd`), run `{baseDir}/scripts/find-sessions.sh --since N` — it lists recent session JSONLs across all project directories in the active profile, newest first.
  Recurring automation often spans repos: scan across projects, not only the current one.
  Read enough of each session for signals; cite each by id or path.

## Distill — recurrence-first signal detection

Cluster evidence into candidate patterns.
For each, record: trigger, evidence, recurrence count, confidence, and target artifact.

| Recurring pattern | Becomes |
|---|---|
| A multi-step tool sequence done manually 2+ times (e.g. fetch→categorize→render) | Skill |
| The same correction or nudge (`no`, `don't`, `instead`, `that's not…`) | CLAUDE.md (project fact) or memory (preference) |
| A stated preference repeated (`I prefer`, `always`, `never`) | Memory |
| The same tool and command approved repeatedly | Permission allowlist |
| Re-explaining the same project context across turns or sessions | CLAUDE.md |
| Repeated web lookups for the same library docs | Memory note or use context7 |
| A skill or agent gave a wrong or user-corrected answer, 2+ times or on explicit correction | Eval task in that skill's `evals/evals.json` |

Also flag wasted-effort smells as supporting evidence, not artifacts on their own: a file read 2+ times with overlapping ranges, a broad search then a narrow one on the same corpus, a subagent dispatched for a one-grep task, or retries of a failing command with no diagnosis between attempts.

## Confidence

- Strong — an explicit user preference, a workflow-changing correction, or the same pattern across 2+ sessions.
- Medium — an accepted workflow, or a repeated tool/validation choice the user relied on.
- Weak — agent-chosen behavior with no user feedback, or one ambiguous instance.
- Contradicted — evidence points both ways; ask the user first.

Promote only Strong and Medium items; list Weak items as "consider" and never auto-apply them.

## Materialize — artifact routing

Route each promoted pattern to exactly one artifact.
Delegate to existing skills; do not reimplement their logic.

- Skill — a recurring multi-step workflow with clear triggers.
  Draft a proposal (name, "Use when…" description, trigger, steps, scripts) and hand it to `superpowers:writing-skills` to author and validate under `skills/<name>/`.
  Mark it local with a `{"repo": null}` `.source.json`.
  Never scaffold skill files by hand.
- CLAUDE.md — a collaborator-visible project fact (build/test commands, invariants, code locations, "always use X helper").
- Memory — a user-private preference (terse vs verbose, tool choices, workflow habits).
  Consolidate before proposing: grep `MEMORY.md` and the entry bodies for the same topic, then choose the action —
  `create` when nothing covers it, `update` when an entry covers it but is stale or incomplete (rewrite that file, keep its filename), `supersede` when a new entry replaces an old one under a better name (name the old file in `supersedes`).
  A contradiction becomes an update or a supersede, never a second entry that recall will return alongside the first.
  Apply both via `{baseDir}/scripts/apply-suggestions.sh`; every memory write stamps `metadata.modified` so recency is visible.
- Eval task — a wrong or corrected answer from an authored skill.
  Write it as a golden task (`name`, the `prompt` that exposed it, the `expected_output` that would have been right) into that skill's `evals/evals.json`, so the fix is checkable later instead of remembered.
  Vendored skills are read-only; propose upstream instead.
- Permission allowlist — repeated approvals of the same tool/command.
  Reference `fewer-permission-prompts` to generate the `.claude/settings.json` entries; do not reimplement its logic.

### CLAUDE.md vs. memory

CLAUDE.md is collaborator-visible; memory is user-private.

- CLAUDE.md-worthy — a project fact any contributor benefits from.
  Before proposing, read the project-root CLAUDE.md (find it with `git rev-parse --show-toplevel`) to avoid duplicates.
- Memory-worthy — anything phrased "I prefer" or "I always"; a personal workflow habit.
- Neither — a one-off event.
  Require 2+ occurrences, or explicit feedback ("remember this"), to promote; otherwise drop.

## Report shape

Emit exactly this structure, by artifact type.
Keep it under about 400 lines; compress, do not truncate.

```
# Harvest Automation

## Scope
<current session | last N days: M sessions across K projects>
- Interaction: <N user / M assistant turns>

## Summary
<P patterns found> → <A skills, B CLAUDE.md, C memory, D permission>

## Proposed skills
- <name> — <"use when" trigger>. Recurs <N>× (<evidence>). → hand to writing-skills.

## Proposed CLAUDE.md additions
Target file: <absolute path, or "propose new at <path>">
(Unified diff — exactly what apply will write.)

## Proposed memory entries
- name: <slug>
  action: <create|update|supersede>   # update/supersede name the existing entry they consolidate
  supersedes: <old-filename>          # supersede only
  type: <feedback|user|project|reference>
  description: <one-liner>
  body: |
    <content; Why: and How to apply: for feedback/project types>

## Proposed eval tasks
- skill: <authored skill name>
  name: <kebab-case task name>
  prompt: <the request that exposed the failure>
  expected_output: <checkable outcome the skill should have produced>

## Proposed permission allowlist
- <tool + command pattern> approved <N>× → see fewer-permission-prompts.

## Consider (weak signal, not auto-applied)
- <pattern> — <evidence>.

## Apply?
Reply: `apply skills`, `apply claude`, `apply memory`, `apply all`, or `skip`.
```

## Apply on confirmation

- `apply skills` — invoke `superpowers:writing-skills` per proposed skill, with the drafted proposal.
  Do not write skill files directly.
- `apply claude` / `apply memory` / `apply evals` / `apply all` — write the payload (schema below) to `/tmp/harvest-automation-<sessionid-or-timestamp>.json`, then run:

```bash
{baseDir}/scripts/apply-suggestions.sh <claude|memory|evals|all> <payload.json>
```

```json
{
  "claude_md": { "path": "/abs/CLAUDE.md", "append": "## Section\n\nBody…\n" },
  "memory": {
    "dir": "/abs/memory",
    "entries": [
      { "filename": "feedback_terse.md",
        "action": "create",
        "content": "---\nname: …\ndescription: …\nmetadata:\n  type: feedback\n---\n\n<body>\n",
        "index_line": "- [Terse output](feedback_terse.md) — prefers short answers" },
      { "filename": "prefer-upstream-sources.md",
        "action": "supersede", "supersedes": "cursor-team-kit-source-repo.md",
        "content": "---\n…\n---\n\n<merged body>\n",
        "index_line": "- [Prefer upstream sources](prefer-upstream-sources.md) — fetch from the original repo, not forks" }
    ]
  },
  "evals": [
    { "skill_dir": "/abs/skills/<name>",
      "entries": [ { "name": "wrong-regime-pick", "prompt": "…", "expected_output": "…", "files": [] } ] }
  ]
}
```

`action` defaults to `create` (skipped if the file exists); `update` replaces an existing file in place; `supersede` writes the new file and retires the one in `supersedes`.
Replaced and retired files are backed up as `<file>.bak.<ts>`, their `MEMORY.md` lines are swapped or dropped, and every written file gets `metadata.modified: <today>`.

`evals` entries are appended to `<skill_dir>/evals/evals.json` (created in the skill-creator shape if absent) with the next free `id`; an entry whose `name` already exists is skipped.

(`apply all` runs CLAUDE.md, memory, and evals together; skills still apply separately, via writing-skills.)

## Anti-patterns

- Do not dump the transcript — the report is the analysis, not a log.
- Do not edit CLAUDE.md or memory files directly — always go through `apply-suggestions.sh` for consistent backups and index updates.
- Do not re-run tools that already ran in-session; reuse prior results.
- Do not use performative praise or emojis; state one genuine strength under `## Strengths` only if one exists, otherwise omit.

## Scripts

```bash
{baseDir}/scripts/find-sessions.sh                 # current session JSONL (most recent for cwd)
{baseDir}/scripts/find-sessions.sh --since 7       # recent session JSONLs (last 7 days), newest first
{baseDir}/scripts/apply-suggestions.sh <scope> <payload.json>   # apply CLAUDE.md / memory / eval-task edits
```

## Troubleshooting

If context was compacted (a system reminder mentions it, or the earliest turns are missing), run `{baseDir}/scripts/find-sessions.sh` and read the earliest portion to recover missed turns.
