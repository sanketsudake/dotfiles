---
name: author-mermaid-diagram
description: >-
  Fixes a mermaid diagram that renders too wide or unreadable in a narrow
  content column on a static-site page.
  Use when adding or fixing a mermaid diagram in a Hugo (or other
  static-site) page, or on triggers "add a diagram", "mermaid", "diagram is
  too wide".
  Covers the width rule, layout direction, the semantic color palette, and
  the browser viewBox check.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Authoring Mermaid Diagrams

Most static-site themes render mermaid from a ` ```mermaid ` fence or a `{{< mermaid >}}` shortcode.
The constraints below apply to both.

## Width Rule

The content column is typically about 800 px wide.
Keep every diagram under 900–950 px natural (viewBox) width.
A wider diagram shrinks until its text is unreadable inline.

Measure in a browser after `hugo server`:

```js
document.querySelector('.mermaid svg').viewBox.baseVal.width
```

Design choices that keep diagrams narrow:

- Prefer `flowchart TB` (top-to-bottom) over `flowchart LR` (left-to-right).
- ≤3 nodes per rank.
- ≤4-word edge labels.
- ≤12 nodes per diagram — split larger ones.
- Avoid side-by-side subgraphs.
  The `direction` attribute on a subgraph is **ignored** when its nodes have external edges.
  Paired subgraphs then force a wide layout regardless.

## Diagram Type Choice

| Type | Use for |
|---|---|
| `flowchart TB` | Component/data flows (default) |
| `sequenceDiagram` | Request/interaction ordering between actors |
| `stateDiagram-v2` | Lifecycles (states and transitions) |

For `sequenceDiagram`: use `autonumber`, keep to ≤4 participants, use short participant names.
Do not use `classDiagram`.
It exceeds the width rule and rarely fits documentation flows.

## Step Numbers on Arrows

Label numbered steps as `-->|"<b>1.</b> description"|`.
The `<b>` tag renders bold via the project's stylesheet.
Never use circled glyphs (①②③).
`sequenceDiagram` uses `autonumber` instead of manual labels.

## Palette — color nodes by semantic role

A single-color theme hides meaning in flow and sequence diagrams.
Apply a small semantic palette via `classDef`, so role reads at a glance in light and dark mode.
Fills use mid-tone Tailwind 400/500 colors, with white text:

| Class | Use for | Fill | Stroke |
|---|---|---|---|
| `leader` | Active / primary actor | `#10b981` | `#047857` |
| `standby` | Passive / waiting | `#94a3b8` | `#475569` |
| `lease` | Coordination primitive (lock, lease, bucket) | `#f59e0b` | `#b45309` |
| `resource` | Resource being acted on | `#fb7185` | `#be123c` |
| `external` | External system (API, gateway) | `#64748b` | `#334155` |
| `process` | Logic / decision / generic step | `#38bdf8` | `#0369a1` |

Rules:
- Only declare the classes a diagram needs.
- Once you class one node, class **every** node — mixing classed and unclassed nodes looks broken.
- Append `classDef` and `class` lines at the bottom of the diagram body, before the closing fence or shortcode.
- Inside a `subgraph`, put the `classDef`/`class` lines **after** the matching `end`.

## Theme notes

Theme-specific gotchas — verify for your theme:

- **Docsy caches partials**: after editing `body-end.html` (or any hook partial), restart `hugo server`.
  Live reload serves the stale partial otherwise.
- **Lightbox keeps SVG ids**: the click-to-zoom lightbox clones the SVG and scopes its embedded CSS to the original `id`.
  Do not strip ids from mermaid output.

Diagrams must be readable inline, without clicking.
The lightbox is a bonus, not a substitute for a well-proportioned diagram.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Used `flowchart LR` with many nodes | Diagram overflows the column, text unreadable | Switch to `flowchart TB` or split the diagram |
| Subgraph `direction LR` with external edges | Layout ignores `direction`, still wide | Restructure — avoid subgraphs with external edges |
| Edited a hook partial without restarting server | Lightbox / theme change not visible | Restart `hugo server` |
| Stripped SVG ids | Lightbox shows unstyled diagram | Keep the mermaid-generated SVG id |
| Single giant diagram > 12 nodes | Too dense, overcrowded | Split into focused smaller diagrams |
