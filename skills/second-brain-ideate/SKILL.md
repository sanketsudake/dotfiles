---
name: second-brain-ideate
description: >
  Mine the knowledge-base wiki for strong, defensible content ideas —
  blog posts, conference talks, internal sessions, threads. Use when
  the user says "ideate", "what should I write about", "find content
  ideas in my wiki", "blog/talk ideas", or wants to turn collected
  knowledge into publishable content. Produces a scored shortlist with
  outlines in output/ and maintains an ideas backlog in wiki/synthesis/.
allowed-tools: Bash Read Write Edit Glob Grep
license: MIT
metadata:
  author: sanketsudake
  version: "1.0"
---

# Second Brain — Ideate

Extract content ideas from the wiki's **structure between pages** — collisions, contradictions, authority clusters, gaps — not from single pages.
Grounded ideation: every idea must cite the wiki pages that back it, so the output is a plan, not a brainstorm.

## Phase 1 — Harvest signals (mechanical)

Collect the raw material cheaply before any judgment:

```bash
# Backlink counts: most-referenced pages are the vault's gravitational centers
grep -roh '\[\[[^]|]*' wiki/ | sed 's/\[\[//' | sort | uniq -c | sort -rn | head -30
# Authority pages: 2+ sources in frontmatter (evidence depth)
grep -l "sources: \[.*,.*\]" wiki/concepts/*.md wiki/entities/*.md wiki/synthesis/*.md 2>/dev/null
# Recorded contradictions (the lint/ingest conventions write these words)
grep -ril "contradict\|disagree\|conflicting" wiki/concepts wiki/synthesis wiki/entities 2>/dev/null
# Tag clusters: co-occurrence shows the vault's topic spine
grep -h "^tags:" wiki/*/*.md | sort | uniq -c | sort -rn | head -20
# Recency: last ~3 log entries show what the user is actively feeding/doing
tail -60 wiki/log.md
```

Also read `wiki/index.md` (and `wiki/synthesis/content-ideas-backlog.md` if it exists — never re-propose an idea already marked picked/drafted/published/dropped).
Read the user's own authored sources (deep pages sourced from their blog) — personal authority is a scoring input.

## Phase 2 — Generate candidates (five patterns)

Walk each pattern against the harvested signals; a candidate is only valid with **2+ supporting wiki pages** attached:

1. **Collision** — two clusters sharing a structural pattern that never cite each other (e.g. an infra maturity model × AI-agent autonomy). Highest yield: the credibility is knowing both sides.
2. **Contradiction** — sources in the vault that disagree; the piece names the variable that decides who's right.
3. **Authority intersection** — concepts with multiple sources *plus* the user's first-person experience (their own deepened posts, their log activity). These survive Q&A.
4. **Gap** — a question the wiki raises that no source answers, especially where the user's recent work *is* an answer.
5. **Fresh × evergreen** — a recent clip that lands on a durable concept already in the vault.

Read the actual candidate pages (not just titles) before keeping a candidate — the connection must be real, not name-similarity.

## Phase 3 — Score

Score each candidate 1–5 on four axes; drop anything under 12 total:

- **Novelty** — would this combination be hard for someone else to write? (Collisions and gaps score high; summaries of one source score 1.)
- **Evidence** — how many wiki pages back each beat of the argument?
- **Authority** — does the user have first-person experience or authored sources here?
- **Audience fit** — is there an obvious venue (their blog's beat, a conference CFP, an internal session, a thread)?

Recommend a **format** per idea: blog post, conference talk, internal session, or thread — match depth of evidence to depth of format (talks need authority ≥4).

## Phase 4 — Output

1. Write the report to `output/content-ideas-YYYY-MM-DD.md`: top 5–10 ideas, each with
   - working title, format, one-paragraph pitch
   - the 3-beat argument, each beat citing its supporting `[[wiki pages]]`
   - score breakdown and the pattern that produced it
2. Create or update `wiki/synthesis/content-ideas-backlog.md`: one line per idea with status `new | picked | drafted | published | dropped`; carry forward prior entries untouched.
   Frontmatter per wiki conventions (tags, sources it draws on, created/updated).
3. Append to `wiki/log.md`:

```
## [YYYY-MM-DD] ideate | N ideas (M new, K carried)
Top: "Working Title A" (collision, 18), "Working Title B" (gap, 16). Backlog: [[Content Ideas Backlog]].
```

4. Report the shortlist to the user and ask which idea to pick; on pick, mark it `picked` in the backlog.

## Conventions

- Ideas are grounded or they don't ship: no candidate without named wiki pages behind every beat.
- The backlog page is the memory across runs; the report in `output/` is the disposable artifact.
- Composes with the rest of the loop: `/second-brain-ingest deepen` the supporting pages of a picked idea first, then draft (e.g. with a blog-writing skill) from the beats.
- Respect vault roles: read `wiki/`, write reports to `output/`, the backlog is the only wiki page this skill maintains.

## Related Skills

- `/second-brain-query` — explore a topic's coverage before or during ideation.
- `/second-brain-ingest` — `deepen` the supporting pages of a picked idea before drafting.
- `/second-brain-lint` — fix broken links/orphans first; a healthy graph yields honest signals.
