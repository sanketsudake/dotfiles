---
name: second-brain-lint
description: >-
  Health-checks the wiki for contradictions, orphan pages, stale claims, and
  missing cross-references. Use when the user says "audit", "health check",
  "lint", "find problems", or wants to improve wiki quality.
allowed-tools: Bash Read Write Edit Glob Grep
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Second Brain — Lint

Health-check the wiki.
Report issues with actionable fixes.

## Audit Steps

Run all checks below.
Present one consolidated report.

### 1. Broken wikilinks

Scan wiki pages for `[[wikilink]]` references.
Verify each target page exists.
Report broken links.

```bash
# Find all wikilinks across wiki pages
grep -roh '\[\[[^]]*\]\]' wiki/ | sort -u
```

Cross-reference the results against files in `wiki/`.

### 2. Orphan pages

Find pages with no inbound links.

For each `.md` file in `wiki/sources/`, `wiki/entities/`, `wiki/concepts/`, `wiki/synthesis/`:
- Extract the page name (filename without extension).
- Search other wiki pages for `[[Page Name]]`.
- Flag the page as an orphan if no other page links to it.

### 3. Contradictions

Find conflicting claims between related pages.
Flag when:
- Two source summaries make opposing claims about the same topic.
- An entity page conflicts with a source summary.
- Dates, figures, or facts differ between pages.

Do not read all page pairs.
If `qmd` is installed, for each entity/concept page run `qmd search "<page title>" --path wiki/`.
Cross-read only the top 5 hits not already wikilinked from that page.
Without `qmd`, restrict pair-reads to pages that share a frontmatter tag.

### 4. Stale claims

Cross-reference source dates with wiki content.
Flag when:
- A concept page cites only old sources, and newer sources exist on the same topic.
- Entity information is not updated despite newer sources mentioning that entity.

### 5. Missing pages

Scan for `[[wikilinks]]` that point to pages that do not exist yet.
These are topics the wiki mentions without a page of their own.
Assess whether each topic warrants a page.

### 6. Missing cross-references

Find pages that discuss the same topics but do not link to each other.
Look for:
- Entity pages that mention concepts without linking them.
- Concept pages that mention entities without linking them.
- Source summaries that cover the same topic but do not reference each other.

Use the qmd candidate search from check 3 to find related, unlinked pages without O(n²) reads.

### 7. Index consistency

Verify `wiki/index.md` is complete and accurate:
- Every page in `wiki/sources/`, `wiki/entities/`, `wiki/concepts/`, `wiki/synthesis/` has an index entry.
- No index entry points to a deleted page.
- Entries sit under the correct category header.

### 8. Data gaps

Based on current wiki coverage, suggest:
- Topics mentioned often but lacking depth.
- Questions the wiki cannot answer well.
- Areas where a web search could fill missing information.

### 9. Un-deepened high-value pages

List light-ingested source pages.
Rank them as deepen candidates.

```bash
grep -l '^ingest: light' wiki/sources/*.md
```

Rank by (a) highlight count in the page, (b) inbound wikilink count (`grep -rc '\[\[Page Title\]\]' wiki/`).
Report the top 5.
Suggest `/second-brain-ingest deepen` for each.

### 10. Junk entities

Find entity pages whose names fail the author-name heuristic: all digits, domain-like, or letterless.
Propose deletion, plus the matching index and log cleanup.

## Report Format

Group findings by severity.

### Errors (must fix)
- Broken wikilinks
- Contradictions between pages
- Index entries pointing to missing pages

### Warnings (should fix)
- Orphan pages with no inbound links
- Stale claims from outdated sources
- Missing pages for frequently referenced topics

### Info (nice to fix)
- Potential cross-references to add
- Data gaps that could be filled
- Index entries that could be more descriptive

For each finding, include:
- **What:** the issue.
- **Where:** the file(s) and line(s).
- **Fix:** what to do about it.

## After the Report

Ask the user:
> "Found N errors, N warnings, and N info items.
> Want me to fix any of these?"

If the user agrees, fix the issues.
Report what changed.

## Log the lint pass

Append to `wiki/log.md`:

    ## [YYYY-MM-DD] lint | Health check
    Found N errors, N warnings, N info items. Fixed: [list of fixes applied].

## When to Lint

Two modes:

- **Quick lint — automatic at the end of every batch ingest.**
  Run cheap mechanical checks only: broken wikilinks (1), index consistency (7), junk-entity scan (10), and a log-to-raw detection round-trip (the unprocessed-file diff from `/second-brain-ingest` must be empty right after a batch).
  If `qmd` is installed, also run `qmd update` so new pages are searchable.
- **Full lint — monthly, on demand, or before major synthesis.**
  Run all checks, including contradictions, stale claims, and deepen candidates.

## Related Skills

- `/second-brain-ingest` — process new sources into wiki pages
- `/second-brain-query` — ask questions against the wiki
