---
name: add-llms-txt
description: >-
  Adds LLM-friendly outputs to a Hugo site: /llms.txt and /llms-full.txt
  indexes plus a per-page markdown twin at <url>/index.md, generated from
  content so they stay in sync.
  Use when the user says "add llms.txt", "make the site agent-friendly", or
  wants a "markdown twin" for pages.
  Hugo sites only.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Add llms.txt + markdown twins to a Hugo site

## Workflow

1. Add the output formats and assignments to the site config.
   Paste the verbatim TOML block below (copied from a working site):

   ```toml
   [outputs]
     home = ["HTML", "RSS", "JSON", "llms", "llmsfull"]
     # Every content page also emits a clean markdown twin at <url>/index.md for
     # LLMs/agents that fetch a single page (rendered by layouts/_default/single.markdown.md).
     page = ["HTML", "markdown"]

   # Dedicated media type so both LLM output formats render with a .txt extension
   # (markdown's own media type would force .md). The two output formats share it,
   # differentiated by baseName.
   [mediaTypes]
     [mediaTypes."text/llms"]
       suffixes = ["txt"]
       delimiter = "."

   [outputFormats]
     [outputFormats.llms]
       mediaType = "text/llms"
       baseName = "llms"
       isPlainText = true       # do not HTML-escape the markdown body
       rel = "alternate"        # head.html auto-emits a <link rel="alternate"> for it
     [outputFormats.llmsfull]
       mediaType = "text/llms"
       baseName = "llms-full"
       isPlainText = true
       rel = "alternate"
     # Per-page markdown twin. Uses Hugo's built-in text/markdown media type (.md);
     # baseName "index" yields <page-dir>/index.md. rel="alternate" makes head.html
     # advertise it on each page.
     [outputFormats.markdown]
       mediaType = "text/markdown"
       baseName = "index"
       isPlainText = true
       rel = "alternate"
   ```

2. Copy the templates from this skill's `assets/` into the site's `layouts/`:
   - `assets/index.llms.txt` → `layouts/index.llms.txt`
   - `assets/index.llmsfull.txt` → `layouts/index.llmsfull.txt`
   - `assets/single.markdown.md` → `layouts/_default/single.markdown.md`

Adjust section names (`"posts"`, `"talks"`) to match the target site's content sections.
If the site has no canonical-URL field, the `canonicalURL` references are no-ops: `.Params.canonicalURL` returns an empty string.

3. Customize `index.llms.txt` for the target site:
   - Set `params.llmsIntro` in `hugo.toml` or `params.toml` to a one-sentence site description for LLM crawlers.
     Example: `llmsIntro = "Technical writing on Kubernetes and platform engineering."` If unset, the template falls back to `"Content by <author.name>."`.
   - Set `params.author.bio` for the About line, or edit the About section directly.

4. Advertise the twin.
   Ensure the head partial emits `<link rel="alternate" type="text/markdown" href="index.md">`.
   Congo does this automatically when `rel = "alternate"` is set on the output format.

5. Verify: use the verify-hugo-build skill (or `hugo --gc --minify` + curl /llms.txt, /llms-full.txt, and a sample <url>/index.md) to confirm the new outputs render before declaring work done.

## Guardrails

- Never edit `public/`.
  These outputs are generated; rebuild the site to regenerate them.
- Allow AI crawlers in `robots.txt` if you want them fetched (GPTBot, ClaudeBot, PerplexityBot, Google-Extended, etc.).
- The `llms-full.txt` template only iterates `"posts"`.
  Update the range filter if the target site uses a different section name.

## Output

`/llms.txt`, `/llms-full.txt`, and per-page `index.md` twins, all build-generated.
