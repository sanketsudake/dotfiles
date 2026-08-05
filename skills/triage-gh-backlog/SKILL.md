---
name: triage-gh-backlog
description: >-
  Scrubs and triages a GitHub repo's open issue/PR backlog: closes
  stale/duplicate/already-shipped/EOL items and categorizes the rest by
  type, area, and priority, like a product manager doing an audit. Use
  when the user says "go through all open issues and PRs and see what
  can be closed", "scrub the outstanding issues", "close stale/duplicate
  items", or wants a one-off backlog cleanup or a recurring triage
  cadence. Backed by gitcrawl (local SQLite mirror, no API-quota burn)
  and portable across OSS repos via --repo plus a per-repo config. Not
  for reading a single issue, or GitHub writes beyond close/label/comment
  (milestones, transfers).
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# triage-gh-backlog

A repeatable, low-risk pipeline to scrub a long-neglected GitHub backlog.
It mirrors all issues and PRs into local SQLite with **gitcrawl**.
A rule engine assigns each thread a disposition: close-stale, close-duplicate, close-implemented, close-eol, pr-archive, needs-info, or keep+categorize.
It produces a reviewable report, then applies approved actions to GitHub via `gh`, gated and capped.

**Core principle:** decide locally and cheaply, with no writes; apply to GitHub separately, gated and capped. gitcrawl's own `close-thread`/`close-cluster` are LOCAL-only — they hide items from future runs, never touch GitHub.
All real closing, labeling, and commenting goes through `gh` in the apply stage.

This skill works with any repo: set `--repo owner/name` and a per-repo `config.<owner>__<repo>.toml`.

## When to use

Not for reading a single issue — use `gh issue view`.
Not for GitHub writes beyond close/label/comment, such as milestones or transfers — do those by hand.

## Prerequisites

Run `bash scripts/scrub.sh doctor` to check: **gitcrawl** (`brew install openclaw/tap/gitcrawl` then `gitcrawl init`), authenticated **gh**, **python3 3.11+**, **sqlite3**.
No OpenAI key is needed — triage uses keyword/FTS matching only.

## The pipeline

Five idempotent stages run via `scripts/scrub.sh`, each reading/writing a per-repo workdir (`~/.cache/issue-pr-scrub/<owner>__<repo>/` by default; override in config).

| Stage | Command | Writes GitHub? | Output |
| --- | --- | --- | --- |
| sync | `scrub.sh sync --repo R [--full]` | no (reads GitHub) | populates gitcrawl SQLite |
| extract | `scrub.sh extract --repo R` | no | `threads.jsonl` |
| triage | `scrub.sh triage --repo R` | no | `triage.jsonl` |
| report | `scrub.sh report --repo R` | no | `report.md`, `triage.csv`, `apply-plan.jsonl` |
| apply | `scrub.sh apply --repo R --auto\|--from F [--execute]` | **yes (gated)** | `ledger.jsonl` |

`scrub.sh protect --repo R [--execute]` adds `keep-open` to the numbers in `keepers.txt` (gated; dry-run default).

`scrub.sh run --repo R [--full]` chains sync→extract→triage→report, never writing.
Use `--full` on the first run for a full backfill; omit it after for incremental runs with a closed-sweep.

**Read the stage contract in `references/pipeline.md` before running.**

For `review`-tier items: copy the approved ones from `apply-plan.jsonl` into `approved.jsonl`, then run `apply.py --from approved.jsonl --execute`.

## Re-reviewing the stale pile (don't bulk-close blindly)

`close-stale` is purely age-based and usually the biggest bucket — treat it as "needs eyes," not "safe to close."
Every row carries type, area, priority, and engagement data.
`report.py` emits **`stale-review.csv`**, sorted by signal (highest reactions+comments, feature/bug first), so keepers float to the top.

```bash
# 1) skim stale-review.csv; put numbers worth keeping into keepers.txt (one per line, '# notes' allowed)
# 2) re-run — keepers become skip and drop out of the apply-plan (instant, no re-sync)
bash scrub.sh triage --repo R && bash scrub.sh report --repo R
# 3) optional: make the protection visible upstream
bash scrub.sh protect --repo R --execute       # adds keep-open to keepers.txt items
# 4) close only what's left
bash scrub.sh apply --repo R --auto --execute
```

## How it decides

The rule engine, taxonomy, and write playbook are documented in:
- `references/triage-rules.md` — every disposition, its heuristic, its tier
- `references/labels.md` — full label taxonomy + mapping + proposed extensions
- `references/write-actions.md` — gh write playbook, comment templates, safety gates
- `references/gitcrawl-reference.md` — the gitcrawl commands + SQLite schema this skill relies on

## Safety gates (apply stage) — non-negotiable

`apply.py` enforces these every run — never bypass them:
- dry-run by default (no `--execute` ⇒ prints only)
- per-run write cap (`apply.max_per_run`, default 25, with pacing)
- tier gate (`--auto` touches only `tier=auto`; `review` requires `--from <curated>`)
- staleness re-check (skips anything closed or touched since extract — re-run the pipeline)
- protected-label re-check
- ledger dedup (a recorded `(number, action)` is never repeated)

## Per-repo config

Copy `scripts/config.example.toml` to `scripts/config.<owner>__<repo>.toml` and tune the `[areas]`/`[types]`/`[versions]` tables — the only repo-specific settings.
`scripts/.gitignore` ignores every `config.*.toml` except the example, so per-repo configs stay local and are never committed.
A worked example for `fission/fission` ships alongside as reference (also git-ignored).
