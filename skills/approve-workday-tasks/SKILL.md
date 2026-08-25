---
name: approve-workday-tasks
description: >-
  Reviews and approves a user's pending Workday "My Tasks" approvals via the
  browser, listing items and approving only the ones explicitly selected.
  Use when the user wants to review or approve pending Workday tasks,
  invoked as /approve-workday-tasks, or mentions Workday "My Tasks",
  pending approvals, Time Entry Approval, or the chrome-cdp CLI.
  Drives the user's real browser via chrome-cdp and logs in through
  login-microsoft-sso.
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.1"
---

# Approve Workday Tasks

Automates the Workday **My Tasks** approval flow with review first, using **`chrome-cdp`** on the user's real, logged-in browser.
It lists pending items and approves only the ones the user selects.
Never approve an item the user did not explicitly choose.

> **Validated live end-to-end**: 3 real Time Entry approvals on 2026-07-16, 2 more on 2026-07-15, and a 6-item sweep on 2026-08-16 (each verified from its detail pane, count 6 → 0).
> Flow: authenticate → open My Tasks → identify the open item → Approve with `--wait-text "Success"` → return to inbox → repeat (Phase 4 covers the dead-end "Success" page).
> Follow **`drive-chrome-cdp`** for the CLI: setup, `--json`/exit codes, `--by name` addressing, `find`, `snap`, `console`/`net`, passkey rule.
> Soft dependency: `login-microsoft-sso` (logged-in tab).
> The `find`-based name discovery below shipped with chrome-cdp 0.2.0 (2026-07-28) and was validated live on 2026-08-16.
> The approve-and-return hop is the recipe **`workday-approve-and-return`** (Phase 4); it lives in the user's `$XDG_CONFIG_HOME/chrome-cdp/recipes/`, not this repo.

## Phase 1 — Authenticate

Follow **`login-microsoft-sso`** (app `workday`) to get a logged-in Workday tab.
Use its tab id.

## Phase 2 — Open My Tasks

- Run `chrome-cdp find "my tasks" --role button --json` to get the inbox control's accessible name (e.g. "Go to My Tasks (N)" or "My Tasks Items") and a `ref` in one call.
  Then run `chrome-cdp click --by name "<that name>" --json` (or `--by ref e<id>`).
- Verify with `chrome-cdp wait --visible "…" --json`, or `snap`/`screenshot`, that the My Tasks list shows.

## Phase 3 — List pending items

- Enumerate with `chrome-cdp snap --json` (roles and names of list items), or `chrome-cdp text "<list selector>" --json`.
  Capture each item's title, type, subject, date, and amount.
- If empty (no items, or "You're all caught up"), report **"No pending tasks"** and stop.
- Otherwise present the items as a numbered list.
  Default is list-only.
  Ask which numbers to approve.

## Phase 4 — Confirm and approve

For each item the user selected, and only those:

1. **Open it.**
   Run `chrome-cdp click --by name "<item title>" --json` (use `snap` for the exact name; add `--nth` if titles repeat).
   Opening auto-selects the first item, not always the top of your enumerated list — never assume which item is on screen.
   Opening may land on a **View Event** page whose only action is **Review**, with a verbose accessible name like `"Review Approval: Awaiting Action by <You>"` (visible text is just "Review").
   Run `chrome-cdp find "review" --role button --json` to get that name, then `chrome-cdp click --by name "Review" --match contains --role button --json` to enter the approval task.
2. **Identify the open item before approving.**
   Do not trust the My Tasks preview label — previews can disagree with the detail page (e.g. "40 hours" shown, 44 on the detail).
   Two reads name the open item unambiguously:
   - `chrome-cdp find "Related Actions Time Entry" --role button --json` — the detail pane's related-actions button carries the item's full name (`Time Entry: <worker> - N hours from MM/DD/YYYY to MM/DD/YYYY for <project>`); the left-hand list's headings carry every item's name, so a `snap --grep "<worker>"` matches the list too and does not tell you which one is open.
   - `chrome-cdp grid "Daily Totals" --json` — the per-day rows (`Mon, 8/10 | Regular Hours | 8`); sum the Hours column and check the dates fall in the named period.
   Approve only if the name's worker/period/hours match a selected item **and** the grid's sum equals the hours in the name.
   If it does not match the selected item, do not approve.
   Re-open the correct item (`--nth` to disambiguate identical titles), or report the mismatch and stop.
3. **Approve and confirm in one call.**
   Run `chrome-cdp click --by name "Approve" --role button --wait-text "Success" --json`.
   `--wait-text` blocks until the "Success!
   Event approved" toast.
   For a **Time Entry Approval** this finalizes it — there is no separate Submit.
   Other task types may show a Submit/OK button; click it by its exact name only if present.
   If `--wait-text` returned ok, the approval landed.
   Else confirm via **Overall Status → "Successfully Completed"** (or `snap.alerts`) — not the top-bar My Tasks badge, which lags.
4. **Return to the inbox.**
   The "Success!
   Event approved" page is a dead end — no navigation, no auto-advance.
   Run `chrome-cdp nav "<Workday home>" --json` (the `WORKDAY_HOME_URL` from `login-microsoft-sso`'s config), then `chrome-cdp wait --idle` and `wait --stable`, then `chrome-cdp click --by name "Go to My Tasks" --match contains --role button --json` (the count is part of the name, so match by prefix).
   The count N decrements by one per approval — an independent check the item cleared.
   Reopening My Tasks auto-opens the first remaining item, so the next iteration starts at step 2, not step 1.
   Steps 3–4 plus the next item's identity reads are the recipe **`workday-approve-and-return`**:

   ```sh
   chrome-cdp recipe run workday-approve-and-return --target <tab id> --set home="$WORKDAY_HOME_URL"
   ```

   Its last two envelopes (`find "Related Actions Time Entry"`, `grid "Daily Totals"`) are the identity of the item now open — check them against the selection before running it again.
   The recipe holds no conditional on purpose: the match is the safety, and it stays in your hands.
   Repeat until every selected item is done.

> Naming note: `--by name` matches the exact accessible name reported by the a11y tree, not the visible label (they differ, as with "Review").
> `find "<few words>"` is the one-call way to get that name (or a `ref`); use `--nth` to disambiguate duplicates.

Finish with a summary: approved, skipped, failed.

## Safety

- Never approve an item the user did not explicitly select.
- The approval page also offers a **Bulk Approve** link — never use it; it approves without the per-item detail check that this skill exists for.
- If an Approve click seems to do nothing, don't re-click blind.
  Run `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` to see the error behind the failed action (reset with `--clear` before a single retry) — a re-click on a slow approval can double-fire.
- For an audit trail, wrap a sweep in `record start` … `record stop -o approvals.gif` (or `session --record`), and review the capture before it leaves the machine — it shows the logged-in session.
- Avoid clicking anything that triggers a native browser dialog (it blocks cdp); prefer in-page controls.
- If login can't be confirmed, or a step fails repeatedly, stop and report rather than improvising.
