---
name: second-brain-review
description: >-
  Resurfaces knowledge from the second-brain wiki: a daily or periodic review
  of highlights, concepts, and stale pages, replacing Readwise's daily
  review. Use when the user says "daily review", "review my highlights",
  "resurface something", "what should I revisit", or wants
  spaced-repetition-style engagement with their wiki.
allowed-tools: Bash Read Write Edit Glob Grep
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Second Brain — Review

Resurface a small, rotating set of the user's own knowledge: highlights, concepts, and stale pages.
This skill replaces Readwise's daily review, using the wiki instead.

## Pick the Set

```bash
python3 {baseDir}/scripts/pick-review.py
```

Returns JSON with about 7 items: 60% highlights, 30% concepts, and the rest are the oldest-updated source pages.
The seed comes from today's date, so same-day re-runs return the same set.
The script excludes items reviewed in the last 30 days.

Flags:

- `--count N`
- `--vault PATH`
- `--exclude-days N`
- `--seed X`

## Present the Review

Show each item conversationally, one small block per item.
Do not dump raw data.

- **Highlight**: Quote it.
  Name the source: *"You highlighted this in [[Page]]: …"*.
  Add one line on why it might matter now.
  Link to another wiki page when a real connection exists.
- **Concept**: State the concept in one or two sentences from its page.
  Ask a light recall prompt: *"How would you explain [[Concept]] in your own words?"*.
  The user may engage or skip.
- **Stale source**: Ask *"[[Page]] hasn't been touched since <date> — still relevant, or archive-worthy?"*

Keep the whole review under one minute to scan.
Engagement with each item is optional; do not lecture the user.

## Capture What the Review Produces

Reviews compound only when their output returns to the wiki.

- If the user draws a connection between items, offer to save it as a `wiki/synthesis/` page (frontmatter + `[[wikilinks]]`, index + log per schema).
- If the user wants more on a light source, hand off to `/second-brain-ingest` deepen.
- If the user flags a stale page as obsolete, note it as a candidate for the next `/second-brain-lint` pass.
  Do not delete it inline.

## Log the Review

Append one entry (append-only):

```
## [YYYY-MM-DD] review | Daily review
Reviewed: [[Page One]], [[Page Two]], [[Concept X]], ... Saved: [[Synthesis Page]] (if any).
```

`pick-review.py` reads the `Reviewed:` wikilinks to avoid repeats within the exclusion window.
Always list every presented page.

## Scheduling (optional)

This skill runs once per invocation, by design.
For a recurring cadence, schedule it externally.
Example: a daily `/schedule` routine, or cron that invokes `/second-brain-review`.
Do not build a loop inside the skill.

## Related Skills

- `/second-brain-query` — dig into anything the review surfaces
- `/second-brain-ingest` — deepen a source the review flags
- `/second-brain-lint` — full health pass; consumes stale/obsolete notes from reviews
