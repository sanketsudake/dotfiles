---
name: fill-workday-timesheet
description: >-
  Fills in the user's Workday timesheet: hours per weekday against a
  project for one week or every unfilled week up to a date, review-first,
  showing the planned hours and waiting for confirmation before saving;
  submits for approval only when asked.
  Use when the user wants to fill in their Workday timesheet ("fill my
  timesheet", "make sure time is entered through the 15th"), invoked as
  /fill-workday-timesheet.
  Drives the user's real Chrome via the chrome-cdp CLI, logging in through
  login-microsoft-sso.
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.1"
---

# Fill Workday Timesheet

Automates Workday's **Enter Time** flow with the **`chrome-cdp`** CLI, in the user's real, logged-in Chrome.
For each week in scope, it proposes hours per weekday against a project, shows the whole plan, and waits for confirmation before saving.
Entering time writes real data.

> ✅ **Validated live (2026-08-16)** — two consecutive weeks (Aug 2–8, Aug 9–15) filled 8h Mon–Fri via Enter Time by Type, saved with the "Your changes have been saved" toast, read back at 40h each; then both submitted for approval through Phase 7 on request.
> Follow **`drive-chrome-cdp`** for the CLI: setup, `--json`/exit codes, `--by name` addressing, `find`, `snap`, `wait --request`, `console`/`net`, passkey rule.
> Soft dependency: `login-microsoft-sso` (logged-in tab, app `workday`).
> The per-week fill is a saved **recipe**, `workday-enter-week` (Phase 5); it lives in the user's `$XDG_CONFIG_HOME/chrome-cdp/recipes/`, not this repo, because its inputs carry the project name.

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

## Phase 2 — Open the Enter Time grid and find the weeks in scope

1. `chrome-cdp find "menu" --role button --json` gets **MENU**'s exact name; `chrome-cdp click --by name "MENU" --json` opens it.
   Open **Time**, then click **"This Week (… Hours)"** or **"Last Week (… Hours)"** under "Enter Time" (labels vary by tenant — `find "this week"` returns the exact rendered name; the hour counts in those labels are a free first read).
2. Wait for the grid with `chrome-cdp wait --idle --json` then `wait --stable`; it shows the title "Enter Time", a week heading (`Aug 9 – 15, 2026`), and a `Sun … Sat` row of "Hours: N".
   `wait --visible "Enter Time"` is not reliable here (it timed out on a loaded page); read the heading instead.
3. **Assert the week heading after every navigation** — `chrome-cdp snap --role heading --json` — and never count clicks.
   `Previous Week`/`Next Week` clicks are occasionally dropped by Workday (one of three was, live), so a loop that assumes "three clicks = three weeks" silently reads the wrong week.
4. **Scope.**
   For "the current week", stop here.
   For "fill through <date>" or "make sure everything is entered", walk back with `Previous Week` from the newest week in scope until a week that already has hours (each week's cell reads `Hours: 0 Hours: 8 …`); every all-zero week between is in scope.
   Also note each week's **Time Period Lockout** marker (`07/16/2026 - 07/31/2026`) — it names a pay period, and a day is locked only if its own date falls inside it.
   Never enter time on a locked day; flag it.
5. Do not touch the week after the last date the user named.

## Phase 3 — Read each week and build the plan

- `chrome-cdp snap --grep "Hours:" --role cell --json` reads a week's `Sun … Sat` headers and "Hours: N" values in one node.
- Propose `DEFAULT_HOURS` Mon–Fri, 0 on weekends, unchanged where a day already meets the target; one row per week in scope.

## Phase 4 — Confirm the whole plan (easy one-tap accept)

Show every week in scope as one table, naming the project and time type above it:

| Week | Sun | Mon | Tue | Wed | Thu | Fri | Sat | Total |
|------|-----|-----|-----|-----|-----|-----|-----|-------|
| Aug 2–8 | 0 | 8 | 8 | 8 | 8 | 8 | 0 | 40 |
| Aug 9–15 | 0 | 8 | 8 | 8 | 8 | 8 | 0 | 40 |

State that the weeks will be **saved, not submitted** (Phase 7 is opt-in).
If the user also wants Engage points for the billed weeks, name them here so one confirmation covers both (`record-engage-activity`, preset `billed-week`, runs after the saves verify).

Present via `AskUserQuestion`, with **Accept** as the default option:

- **Accept** — apply the table as shown and save every week in it.
- **Adjust some days** — the user names only the days that differ (`Fri 8/14 0`, `Wed 8/5 4`); everything else stays at `DEFAULT_HOURS`.

Also accept a compact inline reply naming only exceptions (e.g. `Fri 0`, `Wed 4`, `Mon off`); a bare `accept`/`yes`/`ok` applies as-is.
If anything changed, re-show the final one-line week (e.g. `Mon 8 · Tue 8 · Wed 8 · Thu 8 · Fri 0 = 32h`) and get one final yes.

**Do not save until the user accepts.**

## Phase 5 — Enter the time (Enter Time by Type — preferred)

Do one week at a time: navigate, **assert the heading**, run the recipe, verify (Phase 6), then `Next Week` and repeat.
The whole per-week flow below is the recipe **`workday-enter-week`** (`chrome-cdp recipe show workday-enter-week` prints it; `--dry-run` prints the exact commands):

```sh
chrome-cdp recipe run workday-enter-week --target <tab id> \
  --set path="$WORKDAY_TIMESHEET_TIMETYPE > $WORKDAY_TIMESHEET_PROJECT > Project > Time Entry" \
  --set mon="Mon, 8/3" --set tue="Tue, 8/4" --set wed="Wed, 8/5" --set thu="Thu, 8/6" --set fri="Fri, 8/7" \
  --set h_fri=0        # only the exceptions; h_* default to 8
```

It opens the dialog, sets the Time Type path, fills Mon–Fri, reads the row back, and saves; a failed step aborts before the save.
Its `target: url:myworkday` picks the tab by URL, so pass `--target <id>` when more than one Workday tab is open.
Run it only after Phase 4's acceptance — the last step is the save.
The steps, for when the recipe needs adapting to a tenant:

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
   Run the five identical per-day fills as one **`session`** batch (one held connection, one envelope per line), not five process spawns — which is what the recipe is.
   **If one column fails as `occluded`** while its neighbours fill: on chrome-cdp ≤ 0.2.1 the Tue column did so reproducibly, because Workday's global "Search Workday" box above the dialog shares that column's x-range and the resolver picked it (fixed in the next release, which ranks the header's own grid first and names the cover in the error).
   The fallback that always works: `chrome-cdp value --all "input[data-automation-id=numericInput]" --json` shows which cell is still `0`; read that input's DOM id with `eval` (`[...document.querySelectorAll('input[data-automation-id=numericInput]')][2].id`) and `chrome-cdp fill '[id="<that id>"]' "8" --json`.
   **Never press `Escape` inside this dialog to "clear a popover"** — Workday answers it with a "Discard Changes?" modal; if it appears, click **Continue** (keeps the entered hours), not Discard.
4. Only after confirmation, save and confirm in one call: `chrome-cdp click --by name "Save and Close" --role button --wait-text "saved" --json`.
   `--wait-text` blocks until Workday's "Your changes have been saved" appears — no separate verify.
   If a tenant shows **no toast**, confirm at the XHR level instead: identify the save endpoint once with `chrome-cdp net --xhr --json` after a manual save, then follow the click with `chrome-cdp wait --request "<endpoint substr>" --method POST --json` — the only reliable confirm for a toastless write.

> **Why `select`, not `click`, for the menu option and the cascade prompt:** Workday renders these as portal popups that open on a real pointer sequence, mount briefly collapsed (zero-scale), then animate open, delegating events to capture-phase handlers.
> A single `click` lands mid-animation on a zero-size box, registering as an outside-click that closes the popup.
> `select` dispatches a real `Input.dispatchMouseEvent` at the element's live, occlusion-verified centre, re-reading geometry between the open and the option click — all in one held connection.
> Requires a `chrome-cdp` build with the `select` verb.

Fallback (day-by-day): click an empty day cell → set Time Type (`select`) → set **Hours** via `fill` → click **OK**; repeat per day, slower, not preferred.

## Phase 6 — Verify

- After the save the dialog closes and the week view re-renders; `chrome-cdp snap --grep "Hours:" --role cell --json` re-reads `Sun … Sat` with their "Hours: N" in one node, and `snap.alerts` carries "Your changes have been saved".
  Confirm each day shows the intended hours and the total (`Project Hours 40`) updated — no screenshot needed.
- Report per-week, per-day hours and totals, and say plainly that the weeks are **saved, not submitted**.

## Phase 7 — Review and Submit (opt-in only)

Only when the user explicitly asks to submit ("submit my timesheet", "review and submit").
Saving and submitting are different acts: a saved week is editable; a submitted one goes to the approver.

1. Navigate to the week and **assert its heading**.
2. The week view has a **Review** button whose accessible name is verbose (`Review data:6305`); `chrome-cdp find "Review" --role button --json` returns it.
   **No Review button means the week is already submitted** — report that and move on.
3. Click it; the **Submit Time** dialog shows `Total for <range>` and `<range> : N Hours` — read N and confirm it matches the saved total.
4. `chrome-cdp click --by name "Submit" --role button --wait-text "You have submitted" --json` — the heading "You have submitted" is the confirm; the week view re-renders behind it with the same hours.
5. Repeat per week.
   Steps 2–4 are the recipe **`workday-submit-week`** (`recipe run workday-submit-week --target <id>`); step 1 stays manual because it is the safety.

## Safety

- Never save without the user's explicit confirmation of the per-day plan.
- If a `select`/`fill`/save seems to do nothing, read the tab's own evidence before retrying — not a blind re-click or screenshot: `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` (reset with `--clear`, act, re-read).
- Never enter time on a locked time period; surface it instead.
- Avoid native browser dialogs (they block cdp); prefer in-page controls.
- If a step fails repeatedly or the UI differs, stop and report — don't guess.
- Close the Workday tab you opened when done; a dirty Enter Time by Type dialog left open in the user's browser is a stray save waiting to happen — **Close → Discard** it if a run aborts mid-fill.
