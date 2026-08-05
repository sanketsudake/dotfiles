---
name: generate-og-images
description: >-
  Generates branded 1200x630 social-share (OG/Twitter) card images for a
  site's pages, overlaying title, tags, and brand via Pillow onto an AI,
  image, or gradient background.
  Use when the user says "make an OG image", "social card", or
  "regenerate the share image".
  Generic to any Hugo-style content tree.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Generate social-share (OG) card images

Run when adding a post/talk, after changing a page's title or tags, or to generate the site-wide default card.

## Workflow

```bash
python3 {baseDir}/scripts/gen-og-image.py \
  --brand my.site --author "Full Name" \
  --subtitle "Topic A · Topic B" \
  --sections posts,talks \
  path/to/content/<slug>/index.md
```

- Targets are markdown files or bundle dirs; or `--all-content`; or `--default` for the site card.
- `--brand` / `--author` / `--subtitle` overlay text (no defaults — pass them).
- `--bg FILE` / `--bg-dir DIR` supply backgrounds; `--print-prompts` emits per-item AI prompts to paste into an image tool; absent → gradient.
- `GEMINI_API_KEY` (paid tier) enables AI backgrounds.

## Guardrails

- Output is a 1200×630 PNG; place it where the site's OG templates resolve it (bundle `feature.png`, or `static/og/...`).
- Do not embed the card in the page body.
  It is a social asset only.

## Output

One PNG per target.
