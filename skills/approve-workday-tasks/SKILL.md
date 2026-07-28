---
name: approve-workday-tasks
description: Use when the user wants to review and approve their pending Workday "My Tasks" approvals via the browser — invoked as /approve-workday-tasks. Lists pending items and approves only the ones the user explicitly selects. Drives the user's real Chrome via the chrome-cdp CLI (logs in through login-microsoft-sso).
disable-model-invocation: true
---

# Approve Workday Tasks

Assisted, review-first automation of the Workday **My Tasks** approval flow, driven by the **`chrome-cdp`** CLI (the user's real, logged-in Chrome).
It **lists** the pending items and approves **only** the items the user selects.
Never approve anything the user did not explicitly choose.

> ✅ **Validated live end-to-end** — 3 real Time Entry approvals on 2026-07-16 (and 2 on 2026-07-15): authenticate → open My Tasks → **identify the open item** → Approve with `--wait-text "Success"` → **return to the inbox** and repeat.
> Each approval lands on a dead-end "Success!
> Event approved" page — it does **not** auto-advance to the next task, so you re-open each item from the inbox; the My Tasks count decrements per approval as an independent check.
> Follow the **`drive-chrome-cdp`** skill for the CLI (setup, `--json`/exit codes, `--by name` addressing, `find`, `snap`, `console`/`net`, passkey rule).
> Soft dep: `login-microsoft-sso` (logged-in tab).
> The `find`-based name discovery below arrived with chrome-cdp 0.2.0 (2026-07-28) — it feeds the same validated click path, but has not itself been re-validated live.

## Phase 1 — Authenticate

Follow **`login-microsoft-sso`** (app `workday`) to get a logged-in Workday tab; `use` its tab id.

## Phase 2 — Open My Tasks

- Open the inbox: `chrome-cdp find "my tasks" --role button --json` returns the top-bar inbox control's exact accessible name (e.g. "Go to My Tasks (N)" / "My Tasks Items") plus a `ref` in one call — no full-tree `snap` scan — then `chrome-cdp click --by name "<that name>" --json` (or `--by ref e<id>`).
- Verify it opened: `chrome-cdp wait --visible "…" --json` or `snap`/`screenshot` to confirm the My Tasks list is showing.

## Phase 3 — List pending items

- Enumerate with `chrome-cdp snap --json` (roles + names of the list items) and/or `chrome-cdp text "<list selector>" --json`.
  Capture each pending item's visible title / type / subject / date / amount.
- If empty (Workday shows no items, or "You're all caught up"), report **"No pending tasks"** and stop.
- Otherwise present the items to the user as a numbered list.
  **Default is list-only.**
  Ask which numbers to approve.

## Phase 4 — Confirm and approve

For each item the user selected, and only those:

1. **Open it** from the My Tasks list: `chrome-cdp click --by name "<item title>" --json` (`snap` for the exact name; `--nth` if titles repeat).
   Opening My Tasks auto-selects the first item, and the auto-opened item is **not always the top of the list you enumerated** — so never assume which item is on screen.
   Opening may land on a **View Event** page whose only action is **Review** — its *accessible name* is verbose, e.g. `"Review Approval: Awaiting Action by <You>"` (the visible text is just "Review").
   `chrome-cdp find "review" --role button --json` hands you that exact name (this verbose-name case is `find`'s canonical use), then `chrome-cdp click --by name "Review" --match contains --role button --json` to enter the approval task.
2. **Identify the open item before approving.**
   Positively confirm the task on screen is the one you mean to approve — do **not** trust the My Tasks preview label (previews can disagree with the detail page; e.g. a preview reading "40 hours" for an item whose detail totals 44).
   Read the open approval's worker + period + hours off the detail pane: `chrome-cdp grid --json` (the entries table) or a targeted `chrome-cdp snap --grep "<worker>|Total Hours|from 07" --json`.
   If it does **not** match the selected item (different worker or period), do **not** approve — re-open the correct item (`--nth` to disambiguate identical titles) or report the mismatch and stop.
3. **Approve and confirm in one call:** `chrome-cdp click --by name "Approve" --role button --wait-text "Success" --json` — `--wait-text` blocks until the **"Success!
   Event approved"** toast, so the click and its verification are one step.
   For a **Time Entry Approval** this finalizes it — there is **no** separate Submit.
   Other task types *may* show a Submit/OK; `snap` and click it by its exact name only if present.
   If `--wait-text` returned ok the approval landed; else confirm via the event's **Overall Status → "Successfully Completed"** (or `snap.alerts`) — NOT the top-bar My Tasks badge, which lags.
4. **Return to the inbox for the next item.**
   The approval lands on a **"Success!
   Event approved" page that is a dead end** — no navigation, and it does **not** auto-advance to the next task.
   Go back: `chrome-cdp nav "<Workday home>" --json` (the `WORKDAY_HOME_URL` from `login-microsoft-sso`'s config) → `chrome-cdp wait --stable --json` → `chrome-cdp click --by name "Go to My Tasks (N)" --role button --json`.
   The count **N** decrements by one per approval — use it as an independent confirmation the item cleared — then repeat from step 1 until every selected item is done.
   This return hop repeats identically every iteration — batch it over one held connection with `session`, and once a sweep has run clean, capture the whole loop as a saved **`recipe`** (see `drive-chrome-cdp`, "Saved flows") instead of re-deriving names each run.

> Naming note: exact accessible-name matching (`--by name`) means the string must match what the a11y tree reports, not the visible label (they differ, as with "Review").
> `find "<few words>"` is the one-call way to get that exact name (or a `ref`); use `--nth` to disambiguate duplicates.

Finish with a summary: approved, skipped, and failed.

## Safety

- Never approve an item the user did not explicitly select.
- If an Approve click seems to do nothing, don't re-click blind: `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` show the error behind the failed action (reset with `--clear` before a single retry) — a re-click on a slow approval can double-fire.
- For an audit trail of a sweep, wrap it in `record start` … `record stop -o approvals.gif` (or `session --record`) — and review the capture before it leaves the machine; it shows the logged-in session.
- Avoid clicking anything that triggers a native browser dialog (it blocks cdp); prefer in-page controls.
- If login can't be confirmed or a step fails repeatedly, stop and report rather than improvising.
