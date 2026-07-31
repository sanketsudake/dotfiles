---
name: apply-workday-leave
description: Use when the user wants to apply leave / absence in Workday (sick leave, casual leave, planned leave, comp off, etc.) for one or more days, invoked as /apply-workday-leave. Review-first — it shows the absence plan (dates, type, hours) and waits for confirmation before submitting, then reconciles the timesheet so the leave day carries no project hours. Drives the user's real Chrome via the chrome-cdp CLI (logs in through login-microsoft-sso).
disable-model-invocation: true
license: MIT
metadata:
  author: sanketsudake
  version: "1.0"
---

# Apply Workday Leave

Assisted, review-first automation of the Workday **Request Absence** flow, driven by the **`chrome-cdp`** CLI (the user's real, logged-in Chrome).
It requests an absence for the given date(s) and type, **shows the plan and only submits after the user confirms**, then checks the timesheet for those days and clears any project hours already entered there.
Submitting an absence writes real data and pings the approver — never submit without explicit confirmation.

> ⚠️ **DRAFT — needs live validation.**
> The flow and safety rules are complete, but the Workday calendar / radio / in-page-modal interactions have **not** yet been validated end-to-end against a live tenant.
> On the first real run, go slowly and `snap`-and-verify at each step.
> Follow the **`drive-chrome-cdp`** skill for the CLI (setup, `--json`/exit codes, `--by name` addressing, `find`, `snap`, `wait --request`, `console`/`net`, passkey rule).
> Soft deps: `login-microsoft-sso` (logged-in tab) and `fill-workday-timesheet` (Enter Time grid mechanics, Phase 6).

## Defaults (local config, never committed)

Read defaults from `~/.config/harness-configs/apply-workday-leave/config` (user/tenant-specific, not hardcoded):

```bash
. ~/.config/harness-configs/apply-workday-leave/config
echo "$WORKDAY_LEAVE_DEFAULT_TYPE | $WORKDAY_LEAVE_DEFAULT_HOURS"
```

- `WORKDAY_LEAVE_DEFAULT_TYPE` — the Type of Absence used when the user says "sick leave" without naming the tenant's exact type.
- `WORKDAY_LEAVE_DEFAULT_HOURS` — hours per leave day (Workday usually prefills this).

The type is a default; map the user's words to the tenant's absence types (the prompt lists them) and ask if ambiguous.

## Phase 1 — Authenticate

Follow **`login-microsoft-sso`** (app `workday`) to get a logged-in Workday tab; `use` its tab id so later commands need no `--target`.

## Phase 2 — Open Request Absence

1. Focus the global **Search** and submit: `chrome-cdp type --by name "Search" "Request Absence\n" --json` (the trailing `\n` presses Enter).
   If the field's accessible name differs, `chrome-cdp find "search bar" --role textbox --json` returns the exact name in one call.
2. On the results page, open the **Request Absence** *task* — **not** a home tile.
   `chrome-cdp find "request absence" --role link --json` ranks the Tasks/Reports *link* with its exact name and `ref`, then `chrome-cdp click --by name "Request Absence" --role link --json` (or `--by ref e<id>`).
   (Tiles like "Requests"/"Request Absence" shift and are easy to mis-hit — the `--role link` hard filter guards against it; use `--nth` if two links share the name.)
3. Wait for the dialog: `chrome-cdp wait --visible "…" --json` (a Request Absence dialog control) or `snap` until the "For <user> (Myself)" dialog with a Calendar / Date Range toggle is present.

## Phase 3 — Select the date(s)

- The calendar opens on the current month; step months with the chevrons: `chrome-cdp click --by name "‹" --json` / `"›"` (or their accessible names from `snap`).
- Click each leave day: `chrome-cdp click --by name "<day, e.g. 3>" --json` (confirm the exact day cell name via `snap`; for a contiguous span the Date Range tab also works).
- `chrome-cdp screenshot -o /tmp/leave-dates.png` and read it back to verify the intended day(s) are highlighted, then `chrome-cdp click --by name "Continue" --role button --json`.

## Phase 4 — Fill the absence form

1. Open the **Type of Absence** prompt and select the type: `chrome-cdp click --by name "<type>" --json` (radio list; default from config).
2. Check **Hours (Daily)** — Workday prefills the full day; adjust only for partial days (read via `snap`/`value`, and set with **`fill`** — it replaces the prefilled value, unlike `type` which would append to it).
3. Leave **Comment** empty unless the user wants one.

## Phase 5 — Confirm, then submit

Show the plan as one table before touching Submit:

| Date | Type | Hours |
|------|------|-------|
| Fri Jul 3 | Casual/Sick Leave (IND) | 8 |

Present it via `AskUserQuestion` with **Submit as-is** recommended, plus "add a comment first" and "don't submit".
**Do not** `click "Submit Request"` until the user accepts.
Then: `chrome-cdp click --by name "Submit Request" --role button --json`.
There is **no toast** — confirm the write at the XHR level: `chrome-cdp wait --request "<absence submit endpoint substr>" --method POST --json` right after the click (identify the endpoint once with `chrome-cdp net --xhr --json`).
Then verify via **Manage Absence**: search for it (`type --by name "Search" "Manage Absence\n"`), open it, and `snap`/`screenshot` — the calendar must show the absence block on the date (a clock icon = pending approval) and the Balances panel must reflect the plan.

## Phase 6 — Reconcile the timesheet (clear project hours on the leave day)

An absence does not remove project time already entered for that day — the day would double-count and trip alerts.

1. Open **Time**: `chrome-cdp click --by name "MENU" --json`, then the **Time** app; pick the week containing the leave date (This Week / Last Week / Select Week).
2. On the **Enter Time** grid, read the leave day's column (`snap`/`screenshot`): the absence shows as its own block (e.g. "Casual/Sick Leave (IND) · 8 Hours · Submitted").
3. If the day **also** has a project time block (see `fill-workday-timesheet`):
   - Click the project block → the **Enter Time** dialog opens.
   - `chrome-cdp click --by name "Delete" --role button --json`, then confirm the in-page **Delete Time Block** modal: `chrome-cdp click --by name "OK" --role button --json` ("you may need to resubmit your time" is expected).
4. Re-read the grid: the day should show only the absence hours; the weekly Summary should be consistent.
5. Do **not** Review/Submit the timesheet unless the user explicitly asks.

## Safety

- Never `click "Submit Request"` (Phase 5) without the user's explicit confirmation of dates, type, and hours.
- Deleting a time block (Phase 6) is destructive — only on the confirmed leave day(s), never elsewhere.
- Pre-existing **"Time Period Lockout"** alerts on other (closed) days are noise — surface, don't act; never enter/delete time on a locked day.
- Avoid actions that trigger a native browser dialog (they block cdp); Workday's own in-page modals (Delete Time Block) are fine.
- If a click/submit seems to do nothing, read the tab's own evidence before retrying: `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` (reset with `--clear` first) — never blind re-click a Submit.
- For an audit trail of the first live runs, wrap the flow in `record start` … `record stop -o leave.gif` — review the capture before it leaves the machine (it shows the logged-in session).
- If a step fails repeatedly or the UI differs, stop and report — don't guess.
  Given this is a draft, prefer stopping over improvising.
