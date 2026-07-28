---
name: fill-workday-timesheet
description: Use when the user wants to fill in their Workday timesheet for the current week (hours per weekday against a project), invoked as /fill-workday-timesheet. Review-first — shows the week's planned hours and waits for confirmation before saving. Drives the user's real Chrome via the chrome-cdp CLI (logs in through login-microsoft-sso).
disable-model-invocation: true
---

# Fill Workday Timesheet

Assisted, review-first automation of the Workday **Enter Time** flow, driven by the **`chrome-cdp`** CLI (the user's real, logged-in Chrome).
For the current week it proposes hours per weekday against a project, **shows the whole-week plan, and only saves after the user confirms**.
Entering time writes real data — never save without explicit confirmation.

> ✅ **Validated live (2026-07-28).**
> Three consecutive weeks were filled, saved, and re-verified end-to-end: read the week → propose the plan → confirm → Enter Time by Type → save → `grid`-verify the saved hours.
> Go slowly and `snap`-verify each step.
> Follow **`drive-chrome-cdp`** for the CLI (setup, `--json`/exit codes, `--by name` addressing, `find`, `snap`, `wait --request`, `console`/`net`, passkey rule).
> Soft dep: `login-microsoft-sso` (logged-in tab, app `workday`).
> Once the flow has run clean end-to-end, capture it as a saved **`recipe`** (`recipe new`; inputs: day headers + hours) so later weeks are a `recipe run`, not a re-derivation from `snap` — a flow a skill repeats every run belongs in a recipe.

## Approach — enter the whole week at once

Prefer **Actions → Enter Time by Type**: one dialog, one save, not day-by-day.
Typical week is `DEFAULT_HOURS` on each weekday; only exceptions are days not worked (0).
Read, propose, confirm as a whole, apply once.

## Defaults (local config, never committed)

Read defaults from `~/.config/harness-configs/fill-workday-timesheet/config`; they are user/tenant-specific so they are not hardcoded here:

```bash
. ~/.config/harness-configs/fill-workday-timesheet/config
echo "$WORKDAY_TIMESHEET_TIMETYPE | $WORKDAY_TIMESHEET_PROJECT | $WORKDAY_TIMESHEET_DEFAULT_HOURS"
```

- `WORKDAY_TIMESHEET_TIMETYPE` — e.g. `Project Plan` (the Time Type category).
- `WORKDAY_TIMESHEET_PROJECT` — e.g. `Acme: Sample Project` (the Project; the full leaf is `<project> > Project > Time Entry`).
- `WORKDAY_TIMESHEET_DEFAULT_HOURS` — e.g. `8` (per weekday).

The project/time-type are defaults; let the user override per run.

## Phase 1 — Authenticate

Follow **`login-microsoft-sso`** (app `workday`) to get a logged-in Workday tab; `use` its tab id so later commands need no `--target`.

## Phase 2 — Open the current week's Enter Time grid

1. `chrome-cdp find "menu" --role button --json` for **MENU**'s exact name, `chrome-cdp click --by name "MENU" --json` → open **Time** → click **"This Week (… Hours)"** under "Enter Time" (labels vary by tenant — `find "this week"` returns the exact rendered name).
2. `chrome-cdp wait --visible "Enter Time" --json` (or re-`snap`) for the weekly grid: title "Enter Time", `Sun … Sat` header row, each showing "Hours: N".
3. `chrome-cdp screenshot --json` to read the current state.
4. To work a different week, use the grid's own **Previous Week** / **Next Week** buttons (`role=button`, addressable by accessible name): `chrome-cdp click --by name "Next Week" --role button --json` (or `"Previous Week"`) steps one week at a time.
   For a week further away, the Time app also has a **Select Week** link that opens a jump-to-week dialog.
   That dialog's Date field is **not** a single text input — it is three separate spinbuttons named `Month`, `Day`, `Year`: `chrome-cdp fill --by name "Month" --role spinbutton "07" --json` (repeat for `Day` and `Year`), then `chrome-cdp click --by name "OK" --role button --json`.

## Phase 3 — Read the week and build a full-week plan

- `chrome-cdp snap --json` / `text "<grid selector>" --json` to read each day's current "Hours: N" (Sun–Sat).
- Note any **"Time Period Lockout"** marker; locked only if the day's own date falls in that range — never enter time on a locked day (flag it).
- Before proposing hours, check the worker's approved absences (see Safety) so no billable hours land on a leave day.
- Proposed week: `DEFAULT_HOURS` Mon–Fri, 0 on weekends, unchanged where a day already meets the target.

## Phase 4 — Confirm the whole week (easy one-tap accept)

Show the proposed full week as one table, with the project/time-type named above it:

| Day | Current | Proposed |
|-----|---------|----------|
| Mon 6/29 | 8 | 8 |
| Wed 7/1 | 0 | 8 |

Present via `AskUserQuestion` with an **Accept** option as the default:

- **Accept the week** — apply `DEFAULT_HOURS` on every weekday (Proposed column) and save.
- **Adjust some days** — the user names only the days that differ; everything else stays at `DEFAULT_HOURS`.

Also accept a compact inline reply naming only exceptions (e.g. `Fri 0`, `Wed 4`, `Mon off`); a bare `accept`/`yes`/`ok` applies as-is.
If anything changed, re-show the final one-line week (e.g. `Mon 8 · Tue 8 · Wed 8 · Thu 8 · Fri 0 = 32h`) and take one final yes.

**Do not save until the user accepts.**

## Phase 5 — Enter the time (Enter Time by Type — preferred)

1. Open the dialog with the **`select`** verb, which drives Workday's portal menu where a plain `click` on the option fails (the option closes the menu without opening the modal — see below):
`chrome-cdp select "Actions" "Enter Time by Type" --role button --json`.
The field is the **Actions** button; `select` coordinate-clicks it to open the menu, then clicks the **Enter Time by Type** option.
The Actions menu anchors inconsistently (sometimes it renders mis-positioned and `select` returns `did not render / settle` — a safe no-op, never a wrong click); just re-run `select` and it opens on the next try.
2. Set the project once with **`select`** on the **Time Type** cascade prompt (this is the E3 blocker that `click`/`type` could not open):
`chrome-cdp select "Time Type" "$WORKDAY_TIMESHEET_TIMETYPE > $WORKDAY_TIMESHEET_PROJECT > Project > Time Entry" --role textbox --json` — the config values expand into a `>`-path like `<TimeType> > <Project> > Project > Time Entry`; the exact rendered labels vary by tenant, so confirm them from `snap`/the open prompt.
The tree is **four levels deep**: `select` opens the prompt, drills each category by clicking its row, and selects the `… > Time Entry` leaf (`type=1`), committing a selected-item pill.
Options match by substring, so the config's `Project Plan` matches the rendered `Project Plan Tasks`; `--role textbox` disambiguates the input from the same-named column header; `select` errors (never a false success) if the path is incomplete and the final segment is a category.
The old `type --by name "Time Type" "Time Entry\n"` search-and-Enter is a fallback if a tenant renders a different tree.

> **Trap: a week that already has entries.** If the target week already has time booked, opening **Enter Time by Type** shows a row that is already populated with the Time Type set (e.g. `ShiftLeft: Qwiet Product Dev > Project > Time Entry`).
> Do **not** re-run the Time Type cascade in that case — it is already correct; just fill the empty day columns.
> Re-running the cascade risks creating a second row.

> **Trap: `Auto-fill from Prior Week`.** This button opens its own dialog that requires choosing a week from a `Select Prior Week` dropdown *first*.
> Clicking through blind shows `Prior Week Hours: No items available`, and closing the dialog then raises an in-page `Discard Changes?` modal that must be answered (click `Discard`) before you can get back to the grid.
> Avoid this button — fill the day columns directly instead.

3. Enter each day's hours with **`fill --by cell`** — addresses the hour input by its **day column header**, and *replaces* the cell's `0` (not appends → `80`), so no per-day `snap` for input names and no session-specific ids:
`chrome-cdp fill --by cell "Mon, 7/13" "8" --json` (repeat per weekday; the day headers come from the grid, e.g. `Mon, 7/13` … `Fri, 7/17`).
In a multi-row grid disambiguate with `"<Time Type row>|Mon, 7/13"`.
The five per-day fills are identical argv shapes — run them as one **`session`** batch (one held connection, one envelope per line) instead of five process spawns.
4. Only after confirmation, save: `chrome-cdp click --by name "Save and Close" --role button --json`.
In the validated run **no toast appeared** — `snap.alerts` showed only unrelated content — so don't rely on `--wait-text "saved"`.
Verify the write by re-reading the week instead: `chrome-cdp grid --json` (the Enter Time grid shows "Hours: N" per day once the save has landed).
If a tenant does show a toast, `--wait-text "<toast text>"` on the click is a fine shortcut.
For a toastless tenant, the alternative confirm is at the XHR level: identify the save endpoint once with `chrome-cdp net --xhr --json` after a manual save, then follow the click with `chrome-cdp wait --request "<endpoint substr>" --method POST --json`.

> **Why `select`, not `click`, for the menu option and the cascade prompt:** Workday renders these as portal popups that open on a real pointer sequence, mount briefly collapsed (a zero-scale transform) then animate open, and delegate events to capture-phase handlers.
> A single `click` lands mid-animation on a zero-size box (registering as an outside-click that closes the popup); `select` dispatches a real `Input.dispatchMouseEvent` at the element's live, occlusion-verified centre and re-reads geometry between the open and the option click — all in one held connection.
> (Requires a `chrome-cdp` build with the `select` verb.)

Fallback (day-by-day): click an empty day cell → set Time Type (`select`) → set **Hours** via `fill` → click **OK**.
Repeat per day; slower, not preferred.

## Phase 6 — Verify

- `chrome-cdp grid --json` (or `value --all "[data-automation-id=numericInput]"`) to re-read the week's hours in one call: confirm each day shows the intended hours and the weekly total updated — no screenshot.
- Report a summary: per-day hours and weekly total.
  To do another week, navigate to it (Phase 2, step 4) and repeat Phases 3–6.
- Do **not** click **"Review"**/**"Submit"** (submits the timesheet for approval) unless the user explicitly asks.

## Safety

- Never save without the user's explicit confirmation of the per-day plan.
- If a `select`/`fill`/save seems to do nothing, read the tab's own evidence before retrying: `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` (reset with `--clear`, act, re-read) — not a blind re-click or screenshot.
- Never enter time on a locked time period; surface it instead.
- Check the worker's approved absences before choosing hours: Menu > Time > `My Time Off` (page title "My Absence") lists Absence Requests, readable with `grid` (Date / Day of the Week / Type / Requested / Unit of Time / Status).
- Never put billable hours on an approved leave day — a live run found an approved 8-hour Casual/Sick Leave on a day that also carried 8 billable hours in the timesheet, exactly the conflict this check prevents.
- Avoid native browser dialogs (they block cdp); prefer in-page controls.
- If a step fails repeatedly or the UI differs, stop and report — don't guess.
