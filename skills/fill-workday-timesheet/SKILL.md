---
name: fill-workday-timesheet
description: >-
  Fills in the user's Workday timesheet for the current week: hours per
  weekday against a project, review-first, showing the planned hours and
  waiting for confirmation before saving.
  Use when the user wants to fill in their Workday timesheet, invoked as
  /fill-workday-timesheet.
  Drives the user's real Chrome via the chrome-cdp CLI, logging in through
  login-microsoft-sso.
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Fill Workday Timesheet

Automates Workday's **Enter Time** flow with the **`chrome-cdp`** CLI, in the user's real, logged-in Chrome.
For the current week, it proposes hours per weekday against a project, shows the whole-week plan, and waits for confirmation before saving.
Entering time writes real data.

> ⚠️ **DRAFT — needs live validation.**
> The read/propose/confirm/save/verify loop is complete but not yet validated end-to-end.
> Go slowly; `snap`-verify each step.
> Follow **`drive-chrome-cdp`** for the CLI: setup, `--json`/exit codes, `--by name` addressing, `find`, `snap`, `wait --request`, `console`/`net`, passkey rule.
> Soft dependency: `login-microsoft-sso` (logged-in tab, app `workday`).
> Once it runs clean end-to-end, save it as a **`recipe`** (`recipe new`; inputs: day headers + hours) — later weeks become a `recipe run`, not a re-derivation from `snap`.
> A flow a skill repeats every run belongs in a recipe.

## Approach — enter the whole week at once

Prefer **Actions → Enter Time by Type**: one dialog, one save, not day-by-day.
A typical week uses `DEFAULT_HOURS` on each weekday; exceptions are days not worked (0).
Read, propose, confirm as a whole, then apply once.

## Defaults (local config, never committed)

Read defaults from `~/.config/harness-configs/fill-workday-timesheet/config` (user/tenant-specific, not hardcoded here):

```bash
. ~/.config/harness-configs/fill-workday-timesheet/config
echo "$WORKDAY_TIMESHEET_TIMETYPE | $WORKDAY_TIMESHEET_PROJECT | $WORKDAY_TIMESHEET_DEFAULT_HOURS"
```

- `WORKDAY_TIMESHEET_TIMETYPE` — e.g. `Project Plan` (the Time Type category).
- `WORKDAY_TIMESHEET_PROJECT` — e.g. `Acme: Sample Project` (the Project; the full leaf is `<project> > Project > Time Entry`).
- `WORKDAY_TIMESHEET_DEFAULT_HOURS` — e.g. `8` (per weekday).

The project and time type are defaults; let the user override per run.

## Phase 1 — Authenticate

Follow **`login-microsoft-sso`** (app `workday`) to get a logged-in Workday tab; `use` its tab id so later commands need no `--target`.

## Phase 2 — Open the current week's Enter Time grid

1. `chrome-cdp find "menu" --role button --json` gets **MENU**'s exact name; `chrome-cdp click --by name "MENU" --json` opens it.
   Open **Time**, then click **"This Week (… Hours)"** under "Enter Time" (labels vary by tenant — `find "this week"` returns the exact rendered name).
2. `chrome-cdp wait --visible "Enter Time" --json` (or re-`snap`) waits for the grid: title "Enter Time", `Sun … Sat` header row, each showing "Hours: N".
3. `chrome-cdp screenshot --json` reads the current state.

## Phase 3 — Read the week and build a full-week plan

- `chrome-cdp snap --json` / `text "<grid selector>" --json` reads each day's current "Hours: N" (Sun–Sat).
- Note any **"Time Period Lockout"** marker — locked only if the day's own date falls in that range.
  Never enter time on a locked day; flag it.
- Propose `DEFAULT_HOURS` Mon–Fri, 0 on weekends, unchanged where a day already meets the target.

## Phase 4 — Confirm the whole week (easy one-tap accept)

Show the proposed full week as one table, naming the project and time type above it:

| Day | Current | Proposed |
|-----|---------|----------|
| Mon 6/29 | 8 | 8 |
| Wed 7/1 | 0 | 8 |

Present via `AskUserQuestion`, with **Accept** as the default option:

- **Accept the week** — apply `DEFAULT_HOURS` to every weekday (Proposed column) and save.
- **Adjust some days** — the user names only the days that differ; everything else stays at `DEFAULT_HOURS`.

Also accept a compact inline reply naming only exceptions (e.g. `Fri 0`, `Wed 4`, `Mon off`); a bare `accept`/`yes`/`ok` applies as-is.
If anything changed, re-show the final one-line week (e.g. `Mon 8 · Tue 8 · Wed 8 · Thu 8 · Fri 0 = 32h`) and get one final yes.

**Do not save until the user accepts.**

## Phase 5 — Enter the time (Enter Time by Type — preferred)

1. Open the dialog with the **`select`** verb — a plain `click` on the option fails, closing the menu without opening the modal (see below): `chrome-cdp select "Actions" "Enter Time by Type" --role button --json`.
   `select` coordinate-clicks the **Actions** button open, then clicks **Enter Time by Type**.
   If the menu mis-anchors, `select` returns `did not render / settle` — a safe no-op; re-run it and it opens on retry.
2. Set the project with **`select`** on the **Time Type** cascade prompt — the E3 blocker `click`/`type` cannot open: `chrome-cdp select "Time Type" "$WORKDAY_TIMESHEET_TIMETYPE > $WORKDAY_TIMESHEET_PROJECT > Project > Time Entry" --role textbox --json`.
   Config values expand into a `>`-path; exact labels vary by tenant — confirm them from `snap` or the open prompt.
   The tree is **four levels deep**: `select` drills each category, then selects the `… > Time Entry` leaf (`type=1`), committing a selected-item pill.
   Options match by substring, so `Project Plan` matches the rendered `Project Plan Tasks`; `--role textbox` disambiguates the input from the same-named column header.
   `select` errors — never a false success — if the path is incomplete and the final segment is a category.
   Fallback for a different tenant tree: `type --by name "Time Type" "Time Entry\n"` (search-and-Enter).
3. Enter each day's hours with **`fill --by cell`** — addresses the input by its **day column header** and *replaces* the cell's `0` (not appends → `80`), so no per-day `snap` for input names, no session-specific ids: `chrome-cdp fill --by cell "Mon, 7/13" "8" --json`, repeated per weekday (day headers come from the grid, e.g. `Mon, 7/13` … `Fri, 7/17`).
   In a multi-row grid, disambiguate with `"<Time Type row>|Mon, 7/13"`.
   Run the five identical per-day fills as one **`session`** batch (one held connection, one envelope per line), not five process spawns.
4. Only after confirmation, save and confirm in one call: `chrome-cdp click --by name "Save and Close" --role button --wait-text "saved" --json`.
   `--wait-text` blocks until Workday's "Your changes have been saved" appears — no separate verify.
   If a tenant shows **no toast**, confirm at the XHR level instead: identify the save endpoint once with `chrome-cdp net --xhr --json` after a manual save, then follow the click with `chrome-cdp wait --request "<endpoint substr>" --method POST --json` — the only reliable confirm for a toastless write.

> **Why `select`, not `click`, for the menu option and the cascade prompt:** Workday renders these as portal popups that open on a real pointer sequence, mount briefly collapsed (zero-scale), then animate open, delegating events to capture-phase handlers.
> A single `click` lands mid-animation on a zero-size box, registering as an outside-click that closes the popup.
> `select` dispatches a real `Input.dispatchMouseEvent` at the element's live, occlusion-verified centre, re-reading geometry between the open and the option click — all in one held connection.
> Requires a `chrome-cdp` build with the `select` verb.

Fallback (day-by-day): click an empty day cell → set Time Type (`select`) → set **Hours** via `fill` → click **OK**; repeat per day, slower, not preferred.

## Phase 6 — Verify

- `chrome-cdp grid --json` (or `value --all "[data-automation-id=numericInput]"`) re-reads the week's hours in one call — confirm each day shows the intended hours and the weekly total updated, no screenshot needed.
- Report a summary: per-day hours and weekly total.
  Scope is one week per run.
- Do **not** click **"Review"**/**"Submit"** (submits the timesheet for approval) unless the user explicitly asks.

## Safety

- Never save without the user's explicit confirmation of the per-day plan.
- If a `select`/`fill`/save seems to do nothing, read the tab's own evidence before retrying — not a blind re-click or screenshot: `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` (reset with `--clear`, act, re-read).
- Never enter time on a locked time period; surface it instead.
- Avoid native browser dialogs (they block cdp); prefer in-page controls.
- If a step fails repeatedly or the UI differs, stop and report — don't guess.
  As a draft, prefer stopping over improvising.
