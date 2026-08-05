---
name: report-site-analytics
description: >-
  Pulls a GA4 + Google Search Console report (top pages, queries, CTR,
  near-miss positions) into a dated markdown/JSON summary for an
  SEO/reachability pass.
  Use when the user asks for an "analytics report", "what's my search
  traffic", or a "GSC report".
  Generic to any site with GA4 + Search Console configured.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Report site analytics (GA4 + Search Console)

Run this skill at the start of a reachability or SEO cycle.
It finds low-CTR high-impression pages and near-miss queries.

## Workflow

Get Application Default Credentials with access to the GA4 property and the GSC site.
Set `GA4_PROPERTY_ID` and `GSC_SITE_URL` (or use the flags):

```bash
python3 {baseDir}/scripts/analytics-report.py \
  --property <ga4-numeric-id> \
  --site https://my.site/ \
  --days 28 \
  --out docs/analytics/<date>.md
```

## Guardrails

- Search Console data lags by about 3 days.
  Run cycles about once a month so trends are real.
- Reports may contain traffic data.
  Keep them gitignored.

## Output

A markdown report, plus JSON, of top pages, queries, CTR, and positions.
