---
name: verify-hugo-build
description: >-
  Verifies a Hugo site builds the way the deploy host runs it, not just a
  local shortcut.
  Use when checking "does it build", "verify the site", or after editing
  layouts, SCSS, or content, before declaring work done or pushing.
  Explains why `hugo --gc --quiet` is not enough.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Verify a Hugo Build

Run the same build command the deploy host runs.
This is the only reliable local check.
`hugo --gc --quiet` skips `--minify`, which exercises the PostCSS pipeline.
A build that passes `--gc --quiet` can still fail in production.

## Build doctrine

Run the production build, not a shortcut.

```bash
# If the repo has a build script, use it — it wraps the canonical flags:
./build.sh

# If not, run the equivalent directly:
hugo --minify --printPathWarnings --gc
```

Use the Hugo version the deploy config pins, not a system or Homebrew Hugo.
Find it in the deploy config (for example, `HUGO_VERSION` in `netlify.toml`).
Hugo 0.158+ wraps the PostCSS pipeline in Node's experimental Permission Model, which restricts filesystem access.
This breaks browserslist's parent-directory search and can hang or fail `hugo --minify`.
If the theme records a tested Hugo version, pin to it.

## Reading the output

Any `ERROR` is a hard build failure.
A `WARN` (for example, a missing partial or shortcode) is a soft failure — investigate before pushing.
A clean build prints the full page table untruncated, and the page count rises as expected (+1 for a new page, +N for a new section).

## When to also browser-verify

After editing **layouts or SCSS**, start `hugo server` and load the affected pages in a browser.
A build-clean flag does not catch visual regressions.
Use the `agent-browser` skill to automate browser interaction if needed.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Used `hugo --gc --quiet` | "Clean locally" but deploy fails | Run `hugo --minify --printPathWarnings --gc` (or `./build.sh`) |
| Used Homebrew or system Hugo | `hugo --minify` hangs or errors (`ERR_ACCESS_DENIED`) | Pin to the version in the deploy config |
| Used Hugo non-extended build | SCSS/asset pipeline breaks | Themes with an SCSS/asset pipeline require Hugo **extended** |
