---
name: record-engage-activity
description: Use when the user wants to record an activity in Engage (the org's activity/points platform) — e.g. a billed work week, a phone interview, or an attended course/class (e.g. ImprovingU) — invoked as /record-engage-activity. Fills the Add Activity form (category, type, date, quantity, notes) and submits only after user confirmation; can derive a class's date/hours from Outlook. Drives the user's real Chrome via the chrome-cdp CLI (logs in through login-microsoft-sso).
disable-model-invocation: true
---

# Record Engage Activity

Assisted, review-first automation of the Engage **Add Activity** form, driven by the **`chrome-cdp`** CLI (the user's real, logged-in Chrome).
It fills category, type, date, quantity, and notes, then **shows the entry and the points it will add, and submits only after the user confirms** — submitting writes real data and points.

> ✅ **Validated live (2026-07-16).**
> A real `billed-week` (Direct Revenue › 40 Billable Hour Week, 5 points) was recorded end-to-end: `open` + `wait --idle` → content-based auth (Engage renders "Login with Improving" at the app URL) → Category/Type are native `<select>`s with no accessible name, driven by **`select --by label`** (its native sub-mode) → `fill --by label` for Date/Notes → confirm → submit → `grid` verify.
> The date shifted a day (timezone, see Phase 4) but stayed in-week.
> Go slowly and `snap`-verify each step.
> Follow **`drive-chrome-cdp`** for the CLI (`--json`/exit codes, `--by name`, `find`, `snap`, `wait --request`, `console`/`net`, passkey rule).
> Soft dep: **`login-microsoft-sso`** (app `engage`).

## Defaults & presets (local config, never committed)

Read from `~/.config/harness-configs/record-engage-activity/config` (user/tenant-specific, so not hardcoded here):

```bash
. ~/.config/harness-configs/record-engage-activity/config
# $ENGAGE_ACTIVITY_URL, and presets ENGAGE_PRESET_<NAME>="<Category> > <Type>"
```

- `ENGAGE_ACTIVITY_URL` — the Add Activity page.
- `ENGAGE_PRESET_*` — named presets, each `"<Category> > <Type>"`, e.g.:
  - `ENGAGE_PRESET_BILLED_WEEK="Direct Revenue > 40 Billable Hour Week"`
  - `ENGAGE_PRESET_PHONE_INTERVIEW="Recruiting > Interview - Phone"`
  - `ENGAGE_PRESET_COURSE_ATTENDED="Education/Coaching > ImprovingU Attendance"`

Presets are conveniences; the user can also pick any category/type from the live controls.
A `billed-week` pairs with `fill-workday-timesheet`.

### Education/Coaching (course attendance)

- Types include `ImprovingU Attendance` plus prep/facilitation/instructor variants — `snap` the type control for the live list (each shows its own guidance once selected).
- **Quantity** is *class hours* (1.5 h class → 1); **Notes** names the class (`<course> - <session, instructor>`).
- **Date** is the day attended; if unstated, find the class via Outlook (`login-microsoft-sso` app `outlook`; `snap` the week view for `<title>, <start> to <end>, <date>`) for date/duration.

## Phase 1 — Authenticate

Follow **`login-microsoft-sso`** (app `engage`) to get a logged-in Engage tab; `chrome-cdp use <id>` so later commands need no `--target`.

## Phase 2 — Open the Add Activity form

`chrome-cdp open "$ENGAGE_ACTIVITY_URL" --json` (or `nav` in an existing tab), then `chrome-cdp wait --idle --json` (network-settle — not a fixed sleep).
**Confirm you're actually in, by content not URL:** Engage serves a **"Login with Improving"** login view *at the activity URL* even when unauthenticated — so `chrome-cdp snap --grep "Log ?in" --json`; if a login control shows, `chrome-cdp click --by name "Login with Improving" --json`, `wait --idle`, and re-check (Phase 1 / `login-microsoft-sso` handles this).
Only once the form is present, `snap --region "Add Activity" --json` to locate: **Activity Category**, **Activity Type**, **Date**, **Quantity**, **Notes**, and the submit button ("Add N points").

## Phase 3 — Gather the entry

Determine, asking where not implied: **Activity** — preset name (e.g. `billed-week`, `phone-interview`) or explicit category + type, resolving a preset to its `<Category>` / `<Type>`; **Notes** — required free text (e.g. `"22-26 work week"`, or the candidate/round); **Date** — default today; **Quantity** — default 1.

## Phase 4 — Fill the form

Category/Type are native `<select>`s with **no accessible name** (their labels are separate text) — address them by their **visible label** with `--by label`, which `select` honours (its native-`<select>` sub-mode sets the option):
1. **Activity Category**: `chrome-cdp select --by label "Activity Category" "<Category label>" --json`.
2. `chrome-cdp wait --stable --json` (Type repopulates from the chosen category — a settle, not a fixed sleep), then **Activity Type**: `chrome-cdp select --by label "Activity Type" "<Type label>" --option-match exact --json` (`--option-match exact` avoids a substring collision, e.g. `40 Billable Hour Week` vs `OVER 40 Billable Hour Week`).
3. **Date** (only if not default), **Quantity**, **Notes**: set each with **`fill --by label`** (the Notes/Date labels are separate text nodes, not accessible names — `--by label` finds the control by its visible label, and `fill` replaces the default rather than appending): `chrome-cdp fill --by label "Notes" "<value>" --json`, `chrome-cdp fill --by label "Date" "MM/DD/YYYY" --json`.
   - **Timezone shift**: the widget stores local midnight → UTC, so in a behind-UTC timezone the stored date is the **previous day** — this shifts even *weekly* activities by one (e.g. `07/10` stored as `7/9`).
     Harmless as long as it stays inside the target week; **always verify the submitted row's Date after**, and if you need the exact day set the field to **target + 1**.
   - A date-picker click is sometimes ignored (only highlights); re-check and re-`fill` if unchanged — and if a fill keeps not sticking, `chrome-cdp console --only-errors --json` / `chrome-cdp net --failed --json` show whether the widget threw rather than ignored you.

## Phase 5 — Review and submit

- Re-`snap` (or `screenshot`): the submit button now reads **"Add N points"** — N is the points the chosen type grants.
- Present the full entry — category, type, date, quantity, notes, **and N points** — via `AskUserQuestion`, submit recommended alongside "edit first" / "don't submit".
- Only on explicit confirmation: `chrome-cdp click --by name "Add" --match contains --role button --json` (matches "Add N points" without needing to read N first).
- Engage submits via XHR with no toast — confirm at the request level: `chrome-cdp wait --request "<activity endpoint substr>" --method POST --json` (identify the endpoint once with `chrome-cdp net --xhr --json` after a submit; thereafter it's the reliable write-confirm).
- Then re-`snap`/`text` **Current Activities** to confirm the new row (matching category/type/date/notes) is at the top — this is also where the Phase 4 timezone shift is caught, so always check the row's Date.
  Report a summary.

## Removing an entry (cleanup / testing)

To delete a row from **Current Activities** (e.g. a dummy entry made to test the flow), address that row's **Delete** button by name scoped to the row, so the repeated "Delete" resolves to the right one: `chrome-cdp click --by name "Delete" --in-row "<notes or type of that row>" --role button --json`.
The confirm is an **in-page** Angular **"Are you sure?"** modal (not a native dialog) — `snap` surfaces it (under `alerts`), then `chrome-cdp click --by name "Yes" --role button --json`.
Add `--on-dialog accept` to the Delete click as a defensive guard in case a tenant variant raises a *native* confirm instead (it's a no-op for the in-page modal).
Verify the row is gone with `grid`/`eval`, and take care not to delete a real activity in the same table.

## Safety

- Never submit ("Add N points") without the user's explicit confirmation of the entry.
- Pick category/type by visible accessible name, not position/index — order can change.
- Avoid actions that trigger a native browser dialog (`alert`/`confirm`); they block cdp — or, on an action that might raise one, pass `--on-dialog accept|dismiss` so it's handled instead of wedging the connection.
- If a step fails repeatedly, or a control is a native `<select>` that click-based selection can't drive, stop and report — don't guess.
