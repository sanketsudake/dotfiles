---
name: apply-workday-leave
description: >-
  Requests leave or absence in Workday for one or more days: shows the plan
  (dates, type, hours) for user confirmation before submitting, then
  reconciles the timesheet so the leave day carries no project hours.
  Use when the user wants to apply leave, absence, sick leave, casual leave,
  planned leave, or comp off in Workday, or invokes /apply-workday-leave.
  Drives the user's real browser via the chrome-cdp CLI and logs in through
  login-microsoft-sso.
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Apply Workday Leave

This skill automates the Workday **Request Absence** flow via **`chrome-cdp`** on the user's real, logged-in browser.
It requests absence for given dates and type, shows the plan, and waits for confirmation before submitting — then checks the timesheet and clears any project hours already entered.
Submitting writes real data and notifies the approver; never submit without explicit confirmation.

> ⚠️ **DRAFT — needs live validation.**
> Flow and safety rules are complete; calendar, radio, and modal interactions are unvalidated against a live tenant.
> Go slowly on the first run; verify each step with `snap`.
> Follow **`drive-chrome-cdp`** for CLI setup: `--json`/exit codes, `--by name` addressing, `find`, `snap`, `wait --request`, `console`/`net`, passkey rule.
> Soft deps: `login-microsoft-sso` (logged-in tab), `fill-workday-timesheet` (Enter Time grid, Phase 6).

## Defaults (local config, never committed)

Read defaults from `~/.config/harness-configs/apply-workday-leave/config` (user/tenant-specific — do not hardcode):

```bash
. ~/.config/harness-configs/apply-workday-leave/config
echo "$WORKDAY_LEAVE_DEFAULT_TYPE | $WORKDAY_LEAVE_DEFAULT_HOURS"
```

- `WORKDAY_LEAVE_DEFAULT_TYPE` — Type of Absence to use when the user says "sick leave" without naming the tenant's exact type.
- `WORKDAY_LEAVE_DEFAULT_HOURS` — hours per leave day (Workday usually prefills this).

The type is only a default — map the user's words to the tenant's absence types (the prompt lists them) and ask if ambiguous.

## Phase 1 — Authenticate

Follow **`login-microsoft-sso`** (app `workday`) for a logged-in Workday tab, then `use` its tab ID — later commands need no `--target`.

## Phase 2 — Open Request Absence

1. Focus **Search** and submit: `chrome-cdp type --by name "Search" "Request Absence\n" --json` (trailing `\n` presses Enter).
   If the accessible name differs, `chrome-cdp find "search bar" --role textbox --json` returns it in one call.
2. Open the **Request Absence** *task*, not a home tile.
   `chrome-cdp find "request absence" --role link --json` ranks the Tasks/Reports link with its name and `ref`; then `chrome-cdp click --by name "Request Absence" --role link --json` (or `--by ref e<id>`).
   Tiles like "Requests"/"Request Absence" shift and are easy to mis-click; `--role link` guards against this, and `--nth` handles two links sharing a name.
3. Wait for the dialog: `chrome-cdp wait --visible "…" --json`, or `snap` until the "For <user> (Myself)" dialog with a Calendar / Date Range toggle appears.

## Phase 3 — Select the date(s)

- Calendar opens on the current month.
  Step months with the chevrons: `chrome-cdp click --by name "‹" --json` / `"›"` (names from `snap`).
- Click each leave day: `chrome-cdp click --by name "<day, e.g. 3>" --json` (confirm the cell name via `snap`; a contiguous span can use the Date Range tab).
- `chrome-cdp screenshot -o /tmp/leave-dates.png`, verify the day(s) are highlighted, then `chrome-cdp click --by name "Continue" --role button --json`.

## Phase 4 — Fill the absence form

1. Select the **Type of Absence**: `chrome-cdp click --by name "<type>" --json` (radio list; default from config).
2. Check **Hours (Daily)** — Workday prefills the full day.
   For partial days, read via `snap`/`value` and set with **`fill`**, which replaces the value (`type` would append).
3. Leave **Comment** empty unless the user wants one.

## Phase 5 — Confirm, then submit

Show the plan as one table before touching Submit:

| Date | Type | Hours |
|------|------|-------|
| Fri Jul 3 | Casual/Sick Leave (IND) | 8 |

Present it via `AskUserQuestion`, recommending **Submit as-is**, with "add a comment first" and "don't submit" as alternatives.
**Do not** click "Submit Request" until the user accepts.
Then: `chrome-cdp click --by name "Submit Request" --role button --json`.
There is **no toast** — confirm the write at the XHR level: `chrome-cdp wait --request "<absence submit endpoint substr>" --method POST --json` right after the click (identify the endpoint once with `chrome-cdp net --xhr --json`).
Verify via **Manage Absence**: search (`type --by name "Search" "Manage Absence\n"`), open it, `snap`/`screenshot` — the calendar must show the absence block (clock icon = pending approval) and Balances must reflect the plan.

## Phase 6 — Reconcile the timesheet (clear project hours on the leave day)

An absence does not remove project time already entered — the day would double-count and trip alerts.

1. Open **Time**: `chrome-cdp click --by name "MENU" --json`, then the **Time** app; pick the week with the leave date (This Week / Last Week / Select Week).
2. On the **Enter Time** grid, read the leave day's column (`snap`/`screenshot`) — absence shows as its own block, e.g. "Casual/Sick Leave (IND) · 8 Hours · Submitted".
3. If the day **also** has a project time block (see `fill-workday-timesheet`):
   - Click the block; the **Enter Time** dialog opens.
   - `chrome-cdp click --by name "Delete" --role button --json`, then confirm the **Delete Time Block** modal: `chrome-cdp click --by name "OK" --role button --json` ("you may need to resubmit your time" is expected).
4. Re-read the grid — only absence hours should show, and the weekly Summary should be consistent.
5. Do **not** review or submit the timesheet unless the user explicitly asks.

## Safety

- Never click "Submit Request" (Phase 5) without explicit confirmation of dates, type, and hours.
- Deleting a time block (Phase 6) is destructive — only the confirmed leave day(s), never elsewhere.
- Pre-existing **"Time Period Lockout"** alerts on other days are noise — surface them, don't act, and never enter or delete time on a locked day.
- Avoid actions that trigger a native browser dialog — they block cdp.
  Workday's in-page modals (Delete Time Block) are fine.
- If a click or submit seems to do nothing, check evidence before retrying: `chrome-cdp console --only-errors --json`, `chrome-cdp net --failed --json` (reset with `--clear` first).
  Never blind-retry Submit.
- For an audit trail on first live runs, wrap the flow in `record start` … `record stop -o leave.gif`; review the capture before it leaves the machine — it shows the logged-in session.
- If a step fails repeatedly or the UI differs, stop and report — don't guess.
  Prefer stopping over improvising.
