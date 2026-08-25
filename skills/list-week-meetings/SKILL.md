---
name: list-week-meetings
description: >-
  Lists a week's meetings from the Outlook (Microsoft 365) web calendar,
  grouped by day with time, title, organizer, online/in-person status, and
  meeting status.
  Use when the user asks for their week's meetings, "what's on my calendar
  this week", a meeting list, or invokes /list-week-meetings.
  Drives the user's real, logged-in browser via the chrome-cdp CLI and logs
  in through login-microsoft-sso (app outlook).
  Read-only — never creates, edits, or deletes calendar events.
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# List Week Meetings

This skill reads a week's meetings from the Outlook web calendar.
It uses the `chrome-cdp` CLI to drive the user's real, logged-in browser.
It groups events by day.
It does not create, edit, or delete any event.

> ✅ Validated live (2026-07-16).
> Flow: `open` the calendar, then `wait --idle` for the SPA to render, then run **`snap --region Calendar --role button --grep "[AP]M to" --dedupe`**.
> This command returns only the timed events (about 5 nodes, not the full ~750-node tree).
> No external parsing is needed.
> Follow the **`drive-chrome-cdp`** skill for CLI setup, `--json`/exit codes, `--by name`, `snap` filters, `wait`, and the passkey rule.
> Soft dependency: **`login-microsoft-sso`** (app `outlook`).
> Outlook has no SSO button.
> It auto-authenticates via the shared Microsoft session, so login is only navigate and verify.

## Phase 1 — Open the calendar

Get a logged-in Outlook tab on the **week** view.

- Reuse an existing tab: run `chrome-cdp list --url outlook --json`.
  If a calendar tab exists, `use` its id.
- Otherwise, run `chrome-cdp open "$OUTLOOK_HOME_URL" --json` (URL from `login-microsoft-sso`'s config).
  `open` creates the tab, navigates, and makes it current.
  Outlook auto-authenticates via the shared Microsoft session.
  If it lands on a login/passkey page, follow **`login-microsoft-sso`** (app `outlook`).
- Then run **`chrome-cdp wait --idle --json`**.
  Outlook is an SPA: the load event fires before the calendar renders.
  `--idle` waits for the network to settle.
  Do not use a fixed sleep.

## Phase 2 — Pick the week

- Default to the **current week**.
- For another week: run `chrome-cdp find "next week" --role button --json` (also `"previous"` or `"date range"`).
  This returns the exact names of the arrows and date-range button in one ranked call.
  The validated equivalent is `snap --role button --grep "specific date|Next|Previous" --json`.
  Then run `chrome-cdp click --by name "<name>" --role button --json`.
  Then run `chrome-cdp wait --stable --json` (or `--idle`) for the grid to reload.
  Use a condition, not a fixed sleep.
- Note the displayed range: `chrome-cdp snap --grep "\d.*–.*\d.*20\d\d$" --json` shows the heading (e.g. "12–18 July, 2026").
  Use the first short match as the range.
- If a `snap` shows a **"Filter applied"** button, the calendar is filtered.
  State this in the report — results reflect the user's active filter.
  Clear the filter only if the user asks.

## Phase 3 — Extract events (server-side filtered)

Read the timed events with one filtered snap.
Do not dump the whole tree or parse externally.

```sh
chrome-cdp snap --region "Calendar" --role button --grep "[AP]M to" --dedupe --json
```

- `--grep "[AP]M to"` keeps only nodes whose accessible name has an event time range (e.g. `"AI weekly catchup, 9:30 AM to 10:30 AM, Monday, July 13, 2026, Busy, Recurring event"`).
  `--region "Calendar"` scopes the search to the calendar container.
  `--dedupe` removes virtualized duplicates (the same event rendered at several scroll positions).
  Drop `--region` if it over-scopes.
- **Check completeness:** Outlook announces a count in an aria-live node.
  Run `chrome-cdp snap --grep "Loaded \d+ events" --json` (e.g. "Loaded 4 events").
  Compare this count to your event count.
- **Virtualized off-screen hours:** if the count exceeds your result, the grid virtualizes early-morning or late-evening rows.
  Scroll and re-filter: run `chrome-cdp scroll "<grid selector>" --dy 600 --wheel --json` (`--wheel` triggers the grid's lazy render), then `wait --idle`, then re-run the filtered snap.
  Dedupe across reads.
  Repeat to the bottom of the day.
- Also capture all-day and top-banner items: `chrome-cdp snap --grep "all day|All day" --json`.

## Phase 4 — Parse and present

Parse each accessible name (comma-separated) for: **title**, **start–end time**, **day and date**, optional **location / "Microsoft Teams Meeting" / join URL**, **"By <organizer>"**, and **status** (`Tentative` / `Busy` / `Recurring event` / `Exception`).

- Treat "Microsoft Teams Meeting" or a join URL (Teams/Zoom) as **online**.
  Otherwise treat it as in-person or no location.
- List real **meetings** by default (timed events on the main Calendar).
  Mention all-day items separately.
  Exclude Birthdays and holidays calendars unless the user asks for them.

Present the list grouped by day, sorted by start time.
Example:

```
Mon, Jan 5
  09:00–09:30  Team Standup                 (recurring)
  15:00–15:30  1:1 with Manager             By Jane Doe · tentative
Wed, Jan 7
  16:00–16:30  Project Review               By A. Colleague · Teams
  …
```

End with a count (e.g. "9 meetings across the week").
Note the week range, any active filter, and excluded categories.

## Safety

- Read-only: do not click into events to modify them.
  Do not change calendar settings or the active filter unless asked.
- Avoid actions that trigger a native browser dialog (alert/confirm).
  They block `chrome-cdp`.
- If the grid won't load, or `snap` reads stay empty after scrolling, check `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` first.
  A failed calendar API call can explain an empty grid.
  Then stop and report — do not guess.
