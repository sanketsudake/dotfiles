---
name: readwise-second-brain-sync
description: >-
  Syncs Readwise highlights and Reader documents into the second-brain
  vault's raw/ folder in Obsidian-Web-Clipper format. Use when the user
  says "sync readwise", "pull my readwise highlights", "update raw/ from
  reader", or wants their reading library reflected in the wiki (triggers:
  readwise sync, reader sync, import highlights). Sync only — follow with
  /second-brain-ingest.
allowed-tools: Bash Read Glob Grep
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Readwise → Second-Brain Sync

This skill delivers Readwise and Reader content into the vault's `raw/` folder.
`/second-brain-ingest` then processes these files like web-clipped articles.
This skill only writes `raw/` files and its own state.
It never ingests content and never touches `wiki/`.

Default sync scope (high-signal only):

- **Highlight digests** — one file per highlighted book/article (`<slug>-highlights-<bookid>.md`).
  The skill regenerates the whole file whenever that source gains or changes highlights.
- **Reader docs** — documents in the `archive` and `later` locations (`<slug>-<id8>.md`).
  The Reader AI summary goes in `description:`; the full markdown content is the body.

Not synced: the RSS `feed` location (never), and the unread inbox (`new`) unless `--include-inbox` is passed.

## Prerequisites

- `readwise` CLI installed and authenticated — see the `readwise-cli` skill (`npm install -g @readwise/cli`, `readwise login-with-token <token>`).
- A second-brain vault with `raw/` and `wiki/log.md` (default `~/Documents/sanket-wiki`).

## Run the Sync

```bash
python3 {baseDir}/scripts/sync.py
```

Sync is incremental by default.
Two durable cursors (reader docs, highlights) track progress, so each run fetches only changes since the last run.

| Flag | Effect |
|---|---|
| `--vault PATH` | Vault location (default `$READWISE_SYNC_VAULT`, else `~/Documents/sanket-wiki`) |
| `--full` | Ignore cursors and re-fetch everything (still idempotent — unchanged files are skipped by hash) |
| `--include-inbox` | Also sync unread inbox docs (location `new`) |
| `--dry-run` | Fetch, render, and report without writing any file or state |
| `--limit N` | Cap docs and highlight-books processed (for testing) |
| `--docs-only` / `--highlights-only` | Sync a single stream |
| `--state-dir PATH` | Override state location (also `$READWISE_SYNC_STATE_DIR`) |

## Interpret the Report

- **NEW** — files not yet ingested.
  `/second-brain-ingest` auto-detects them.
- **UPDATED** — previously ingested files whose raw content changed (new highlights, an edited article).
  Ingest skips these unless named, so pass the listed filenames explicitly.
- **UNCHANGED** — rendered content matches the last sync.
  Nothing is written.
- **Pending re-ingest carried** — UPDATED files from earlier runs with no newer ingest entry in `wiki/log.md`.
  The entry clears once the file is re-ingested.

## Hand Off

After a sync with NEW or UPDATED files, run `/second-brain-ingest`:

- NEW files are detected automatically (batch mode handles many at once).
- UPDATED files must be named explicitly, e.g. "re-ingest raw/some-article-01jxyz.md (3 new highlights)".

## State and Config

State lives at `~/.local/state/readwise-second-brain-sync/state.json`.
It holds the two cursors, a per-document and per-book file registry (filenames are minted once and reused even if titles change), content hashes, and the pending re-ingest ledger.
To rebuild state, delete the file and run `--full`.
Hash gating leaves raw files with unchanged content untouched.

## Troubleshooting

- **Auth expired** — a CLI call fails with an auth error.
  Re-run `readwise login-with-token <token>` (token from https://readwise.io/access_token).
- **One stream failed** — the other stream still completes.
  The failed stream's cursor does not advance, so the next run re-fetches from the same point.
  The exit code is non-zero in that case.
- **A file reports UNCHANGED but looks stale** — hashes exclude only the volatile `created`/`updated` dates.
  Run `--full --dry-run` to check what would change.

## Related Skills

- `readwise-cli` — the CLI this skill drives
- `/second-brain-ingest` — processes the synced files into wiki pages
- `/second-brain-lint` — health-checks the wiki afterwards
