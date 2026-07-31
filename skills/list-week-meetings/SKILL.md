---
name: list-week-meetings
description: Use when the user wants a list of their meetings for a week from the Outlook (Microsoft 365) calendar — invoked as /list-week-meetings. Read-only: it reads the week's events and presents them grouped by day (time, title, organizer, online/in-person, status). Drives the user's real Chrome via the chrome-cdp CLI (logs in through login-microsoft-sso, app outlook).
disable-model-invocation: true
license: MIT
metadata:
  author: sanketsudake
  version: "1.0"
---

# List Week Meetings

Read-only summary of a week's meetings from the **Outlook** web calendar, driven by the **`chrome-cdp`** CLI (the user's real, logged-in Chrome).
It reads the calendar's events and presents them grouped by day; it never creates, edits, or deletes anything.

> ✅ **Validated live (2026-07-16).**
> Streamlined flow: `open` the calendar → `wait --idle` for the SPA to render → **`snap --region Calendar --role button --grep "[AP]M to" --dedupe`** returns just the timed events, server-side filtered (≈5 nodes, not the whole ≈750-node tree — no external parsing).
> Follow the **`drive-chrome-cdp`** skill for the CLI (setup, `--json`/exit codes, `--by name`/`snap` filters/`wait`, passkey rule).
> Soft dep: **`login-microsoft-sso`** (app `outlook`) — Outlook has **no** SSO button and auto-authenticates via the shared Microsoft session, so login is just navigate + verify.

## Phase 1 — Open the calendar

Get a logged-in Outlook tab on the **week** view:
- Reuse an existing one: `chrome-cdp list --url outlook --json` — if a calendar tab is there, `use` its id.
- Otherwise `chrome-cdp open "$OUTLOOK_HOME_URL" --json` (from `login-microsoft-sso`'s config) — `open` creates the tab, navigates, and makes it current.
  Outlook auto-authenticates via the shared Microsoft session; if it lands on a login/passkey page, follow **`login-microsoft-sso`** (app `outlook`).
- Then **`chrome-cdp wait --idle --json`** — Outlook is an SPA, so the load event fires long before the calendar renders; `--idle` waits for the network to settle (don't guess a fixed sleep).

## Phase 2 — Pick the week

- Default to the **current week**.
- For another week: `chrome-cdp find "next week" --role button --json` (likewise `"previous"` / `"date range"`) returns the exact names of the arrows and date-range button in one ranked call (the snap-grep `snap --role button --grep "specific date|Next|Previous" --json` is the validated equivalent), then `chrome-cdp click --by name "<name>" --role button --json`, and `chrome-cdp wait --stable --json` (or `--idle`) for the grid to reload — a condition, not a fixed sleep.
- Note the displayed range: `chrome-cdp snap --grep "\d.*–.*\d.*20\d\d$" --json` surfaces the heading (e.g. "12–18 July, 2026") — the first short match is the range.
- If a **"Filter applied"** button shows up in a `snap`, the calendar is filtered — say so in the report (results reflect the user's active filter).
  Only clear it if the user asks.

## Phase 3 — Extract events (server-side filtered)

Read just the timed events with one filtered snap — no whole-tree dump, no external parsing:

```sh
chrome-cdp snap --region "Calendar" --role button --grep "[AP]M to" --dedupe --json
```

- `--grep "[AP]M to"` keeps only nodes whose accessible name carries an event time range (e.g. `"AI weekly catchup, 9:30 AM to 10:30 AM, Monday, July 13, 2026, Busy, Recurring event"`); `--region "Calendar"` scopes to the calendar container; `--dedupe` collapses the virtualized duplicates (the same event rendered at several scroll positions).
  Drop `--region` if it over-scopes.
- **Cross-check completeness:** Outlook announces a count in an aria-live node — `chrome-cdp snap --grep "Loaded \d+ events" --json` (e.g. "Loaded 4 events") — compare it to your event count.
- **Virtualized off-screen hours:** if the count says more events than you got, the grid virtualizes early-morning / late-evening rows.
  Scroll and re-filter: `chrome-cdp scroll "<grid selector>" --dy 600 --wheel --json` (the `scroll` verb — `--wheel` for the grid's lazy render), then `wait --idle` and re-run the filtered snap; dedupe across reads.
  Repeat to the bottom of the day.
- Capture all-day / top-banner items too: `chrome-cdp snap --grep "all day|All day" --json`.

## Phase 4 — Parse and present

Parse each accessible name (comma-separated): **title**, **start–end time**, **day + date**, optional **location / "Microsoft Teams Meeting" / join URL**, **"By <organizer>"**, and **status** (`Tentative` / `Busy` / `Recurring event` / `Exception`).

- Treat "Microsoft Teams Meeting" or a join URL (Teams/Zoom) as **online**; otherwise in-person / no location.
- By default list real **meetings** (timed events on the main Calendar).
  Mention all-day items separately, and exclude Birthdays / holidays calendars unless the user wants them.

Present grouped by day, sorted by start time, e.g.:

```
Mon, Jan 5
  09:00–09:30  Team Standup                 (recurring)
  15:00–15:30  1:1 with Manager             By Jane Doe · tentative
Wed, Jan 7
  16:00–16:30  Project Review               By A. Colleague · Teams
  …
```

End with a count (e.g. "9 meetings across the week") and note the week range, any active filter, and excluded categories.

## Safety

- Read-only — do not click into events to modify them, and do not change calendar settings or the active filter unless asked.
- Avoid actions that trigger a native browser dialog (alert/confirm) — they block `chrome-cdp`.
- If the grid won't load or `snap` reads come back empty after scrolling, check `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` first — a failed calendar API call explains an empty grid — then stop and report rather than guessing.
