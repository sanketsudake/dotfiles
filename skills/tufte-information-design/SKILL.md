---
name: tufte-information-design
description: >-
  Applies Edward Tufte's information-design principles to any information
  display — slides/decks, documents, blog posts, dashboards, HTML
  artifacts, tables, diagrams, emails — when creating or reviewing one for
  clarity.
  Use on triggers like "apply Tufte", "make this clearer", "less
  cluttered", "too busy", "chartjunk", "improve information density",
  "review this slide/report/dashboard/diagram/table for clarity", "is this
  chart misleading".
  A principles and review lens, not a builder — chart construction
  mechanics (marks, palettes, axes) belong to a dedicated dataviz skill
  when one is available; deck/doc file mechanics to pptx/docx; visual
  styling direction to a frontend-design skill when one is available.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Tufte Information Design

Apply Edward Tufte's principles to any display of information, in any medium.
The source books are *The Visual Display of Quantitative Information*, *Envisioning Information*, *Visual Explanations*, and *Beautiful Evidence*.

## Core stance

Maximize reasoning per unit of viewer attention.

Clutter and confusion are design failures, not attributes of information.
Do not fix a failed display with decoration or with "dumbing it down".
Remove what does not inform.
Sharpen what does.
Integrate evidence with the words around it.
Well-designed density beats sparse vagueness: audiences handle complexity fine when the design carries it.

## The seven principles

Each principle has a rule and a test.
Run the test on any display.

### 1. Show the evidence

**Rule:** ink (or pixels) must present information.
Maximize the share that does (the data-ink ratio).
**Test:** remove the element.
Is information lost?
If not, it never earned its place.

### 2. Tell the truth about it

**Rule:** visual effect must be proportional to the effect in the data.
Lie Factor = (size of effect in graphic) / (size of effect in data).
Keep it between 0.95 and 1.05.
**Test:** measure the biggest visual contrast in the display.
Does the underlying data show a contrast of the same magnitude?

### 3. Erase what doesn't inform

**Rule:** chartjunk — moiré patterns, heavy grids, self-promoting "duck" decoration — competes with content and always loses the viewer's trust.
**Test:** delete the element and squint.
Did the message survive intact, or get clearer?

### 4. Layer and separate

**Rule:** visual elements interact — two elements side by side create a third perceived effect (1 + 1 = 3 in visual noise).
Mute structural elements (grids, borders, boxes).
Reserve intensity for content.
**Test:** is the loudest ink on the display the most important information?

### 5. Enable comparison

**Rule:** the question is always "compared to what?"
Use small multiples, parallel structure, and shared scales so the eye can compare within a single span of attention.
**Test:** can a viewer compare the things that matter without re-reading, scrolling, or holding numbers in memory?

### 6. Integrate evidence with narrative

**Rule:** words, numbers, and images belong together.
Label data directly.
Embed word-sized graphics (sparklines) in text.
Never orphan an exhibit from the claim it supports.
**Test:** does any exhibit require a legend hunt, a caption hunt, or a "see figure 3" round trip?

### 7. Respect the audience

**Rule:** to clarify, add detail — show complexity well rather than hiding it.
Audiences are not stupid, but their attention is finite.
**Test:** did the revision raise the resolution of the content, or merely cut content to look cleaner?

## Workflow

Use this loop whether creating a display or reviewing one.

1. **Identify the one claim.**
   What must the viewer understand or decide?
   If there are several independent claims, split into several displays.
2. **Choose the display that serves the claim.**
   Comparison → small multiples or a table.
   Trend → line or sparkline.
   Process or relationship → diagram.
   Argument → prose.
   Lookup → table.
   Precise values → table, not chart.
3. **Strip non-information.**
   Run the chartjunk sweep and data-ink audit from the checklist.
   Direct-label instead of using legends.
   Mute structure.
4. **Verify.**
   Run the integrity scan (Lie Factor, baselines, scales).
   Run the squint, newspaper, and necessity tests from `references/review-checklist.md`.

## Medium routing

Load the matching section of `references/media-applications.md` for the display at hand.

| Medium | Section | Related skills |
|--------|---------|----------------|
| Slides & decks | Slides & decks | `pptx` for file mechanics |
| Documents & blog posts | Documents & blog posts | `write-hugo-blog-post`, `docx` |
| Dashboards & HTML artifacts | Dashboards & HTML artifacts | a dataviz skill (when available) for marks/palettes |
| Tables | Tables | `xlsx` for spreadsheet mechanics |
| Diagrams | Diagrams | `author-mermaid-diagram` for mermaid specifics |
| Email & short-form | Email & short-form | — |

This skill governs *what to show, what to cut, and whether the display tells the truth*.
Construction mechanics stay with the related skills above.
Visual styling direction stays with a frontend-design skill when one is available.

## References

- `references/principles.md` — the full principle reference across all four books.
  Load it for the reasoning, violation catalogs, or redesign moves behind a principle.
- `references/media-applications.md` — per-medium application guides.
  Load the section for the medium you are working in.
- `references/review-checklist.md` — the audit checklist.
  Load it when reviewing an existing display or finalizing a new one.
