---
name: second-brain-ideate
description: >-
  Mines the knowledge-base wiki for strong, defensible content ideas — blog
  posts, conference talks, internal sessions, threads. Use when the user says
  "ideate", "what should I write about", "find content ideas in my wiki",
  "blog/talk ideas", or wants to turn collected knowledge into publishable
  content. Produces a scored shortlist with outlines in output/ and maintains
  an ideas backlog in wiki/synthesis/.
allowed-tools: Bash Read Write Edit Glob Grep
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Second Brain — Ideate

Extract content ideas from structure between wiki pages: collisions, contradictions, authority clusters, gaps.
Do not extract ideas from single pages.
Every idea must cite the wiki pages that support it.
The output is a plan, not a brainstorm.

## Phase 1 — Harvest signals (mechanical)

Collect raw signals before you judge them:

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

Read `wiki/index.md`.
If `wiki/synthesis/content-ideas-backlog.md` exists, read it too.
Do not repropose an idea already marked picked, drafted, published, or dropped.
Read the user's own authored sources (deep pages from their blog).
Personal authority is a scoring input.

## Phase 2 — Generate candidates (five patterns)

Apply each pattern to the harvested signals.
A candidate needs 2+ supporting wiki pages to be valid:

1. **Collision** — two clusters share a structural pattern but never cite each other (example: an infra maturity model and AI-agent autonomy).
   Highest yield — credibility comes from knowing both sides.
2. **Contradiction** — vault sources disagree.
   Name the variable that decides who is right.
3. **Authority intersection** — concepts with multiple sources plus the user's first-person experience (deepened posts, log activity).
   These survive Q&A.
4. **Gap** — a question the wiki raises with no source answer, especially where the user's recent work answers it.
5. **Fresh × evergreen** — a recent clip that lands on a durable concept already in the vault.

Read the candidate pages, not just titles, before you keep a candidate.
The connection must be real, not name-similarity.

## Phase 3 — Score

Score each candidate 1–5 on four axes.
Drop candidates scoring under 12 total:

- **Novelty** — would this combination be hard for someone else to write?
  Collisions and gaps score high.
  A summary of one source scores 1.
- **Evidence** — how many wiki pages back each beat of the argument?
- **Authority** — does the user have first-person experience or authored sources here?
- **Audience fit** — is there an obvious venue (their blog's beat, a conference CFP, an internal session, a thread)?

Recommend a **format** per idea: blog post, conference talk, internal session, or thread.
Match evidence depth to format depth — talks need authority ≥4.

## Phase 4 — Output

1. Write the report to `output/content-ideas-YYYY-MM-DD.md`.
   Include the top 5–10 ideas.
   For each idea, give:
   - working title, format, one-paragraph pitch
   - the 3-beat argument, each beat citing its supporting `[[wiki pages]]`
   - score breakdown and the pattern that produced it
2. Create or update `wiki/synthesis/content-ideas-backlog.md`.
   Use one line per idea with status `new | picked | drafted | published | dropped`.
   Carry forward prior entries untouched.
   Add frontmatter per wiki conventions (tags, sources it draws on, created/updated).
3. Append to `wiki/log.md`:

```
## [YYYY-MM-DD] ideate | N ideas (M new, K carried)
Top: "Working Title A" (collision, 18), "Working Title B" (gap, 16). Backlog: [[Content Ideas Backlog]].
```

4. Report the shortlist to the user.
   Ask which idea to pick.
   Mark the picked idea `picked` in the backlog.

## Conventions

- Ground every idea: no candidate without named wiki pages behind every beat.
- The backlog page is memory across runs; the report in `output/` is disposable.
- Composes with the rest of the loop: run `/second-brain-ingest deepen` on the supporting pages of a picked idea first, then draft (e.g. with a blog-writing skill) from the beats.
- Respect vault roles: read `wiki/`, write reports to `output/`.
  The backlog is the only wiki page this skill maintains.

## Related Skills

- `/second-brain-query` — explore a topic's coverage before or during ideation.
- `/second-brain-ingest` — `deepen` the supporting pages of a picked idea before drafting.
- `/second-brain-lint` — fix broken links/orphans first; a healthy graph yields honest signals.
