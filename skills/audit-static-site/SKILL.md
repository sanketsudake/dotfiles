---
name: audit-static-site
description: >-
  Crawls a built static-site output directory and flags SEO/UX issues —
  titles, meta descriptions, alt text, thin/orphan/duplicate pages — before
  publishing. Use when the user says "audit the site", "SEO check", or
  "check the build for SEO". Generic to any static site whose output is
  plain HTML.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Audit a built static site

Run this after a production build, before publishing.
Use `--check` as a gate in an improvement loop; it exits non-zero on any ERROR.

## Workflow

Run the vendored script against the built output:

```bash
python3 {baseDir}/scripts/site-audit.py \
  --public public \
  --site-suffix " | My Site" \
  --sections posts,talks \
  --out docs/audit/<date>.md
```

- `--public` — built output dir (default `public`).
- `--site-suffix` — trailing site-name string appended to every `<title>`; stripped before length checks.
- `--sections` — comma-separated content section dirs to audit.
- `--check` — exit 1 on any ERROR.
  Use in CI or loops.
- `--min-words` — thin-content threshold (default 300).

The script flags:

- over/under-length titles and descriptions
- missing meta description
- images without alt text
- thin pages
- orphan pages
- duplicate titles or descriptions

## Guardrails

- Read the BUILT output, not `content/`.
  Rebuild first.
- Defaults are generic SEO ranges.
  Override per project; do not hardcode.

## Output

A markdown report grouped by severity, or a CI exit code with `--check`.
