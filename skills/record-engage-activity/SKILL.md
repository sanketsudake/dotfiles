---
name: record-engage-activity
description: >-
  Fills and submits the Engage Add Activity form (category, type, date,
  quantity, notes) via the chrome-cdp CLI, showing the entry and points
  before submitting.
  Use when the user wants to record an activity in Engage (the org's
  activity/points platform) — e.g. a billed work week, a phone interview,
  or an attended course/class (e.g. ImprovingU) — invoked as
  /record-engage-activity, with or without an Engage activity URL.
  Also handles an Engage share link (an activity URL carrying a
  `?guid=…`) that arrives prefilled, where the job is to cross-verify and
  submit, not to fill.
  Can derive a class's date/hours from Outlook.
  Logs in via login-microsoft-sso.
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.1"
---

# Record Engage Activity

Assisted, review-first automation of the Engage **Add Activity** form, driven by the **`chrome-cdp`** CLI (the user's real, logged-in Chrome).
It fills category, type, date, quantity, and notes, then shows the entry and points before submitting.
Submit only after the user confirms — it writes real data and points.

> ✅ **Validated live (2026-07-16)** — `billed-week` (Direct Revenue › 40 Billable Hour Week, 5 points), end-to-end via Phases 1–5.
> Date shifted by one day (timezone; see Phase 4) but stayed in-week.
>
> ✅ **Validated again (2026-07-29), via a `?guid=…` share link** — course attendance (Education/Coaching › ImprovingU Key Course Attendance, 2 points), through the [fast path](#fast-path--a-guid-share-link-skips-phases-34).
>
> ✅ **Validated again (2026-08-16)** — two `billed-week` entries in one session, right after `fill-workday-timesheet` saved the weeks; both confirmed by `POST …/CreateOrEdit` → 200 and the new top rows.
> Both stored dates were one day earlier than entered (see Phase 4).
> The fill is the recipe **`engage-fill-activity`** (Phase 4); it lives in the user's `$XDG_CONFIG_HOME/chrome-cdp/recipes/`, not this repo.
> Confirmed by `POST .../CreateOrEdit` → 200 (Phase 5) and the new top row; date did **not** shift this time.
>
> Go slowly and `snap`-verify each step.
> Follow **`drive-chrome-cdp`** for the CLI (`--json`/exit codes, `--by name`, `find`, `snap`, `wait --request`, `console`/`net`, passkey rule).
> Soft dep: **`login-microsoft-sso`** (app `engage`).

## Defaults & presets (local config, never committed)

Read from `~/.config/harness-configs/record-engage-activity/config` (user/tenant-specific — not hardcoded here):

```bash
. ~/.config/harness-configs/record-engage-activity/config
# $ENGAGE_ACTIVITY_URL, and presets ENGAGE_PRESET_<NAME>="<Category> > <Type>"
```

- `ENGAGE_ACTIVITY_URL` — the Add Activity page.
- `ENGAGE_PRESET_*` — named presets, each `"<Category> > <Type>"`, e.g.:
  - `ENGAGE_PRESET_BILLED_WEEK="Direct Revenue > 40 Billable Hour Week"`
  - `ENGAGE_PRESET_PHONE_INTERVIEW="Recruiting > Interview - Phone"`
  - `ENGAGE_PRESET_COURSE_ATTENDED="Education/Coaching > ImprovingU Attendance"`

Presets are conveniences; pick any category/type from the live controls instead.
A `billed-week` pairs with `fill-workday-timesheet`.

### Catch-up: which billed weeks are missing

When the ask is "capture the eligible points" rather than one named week, read **Current Activities** first — `chrome-cdp text --article --json` on the activity page returns every row as `Category … Type … Date M/D/YYYY … Notes <text>` — and list the `40 Billable Hour Week` rows.
The weeks Workday has saved (from `fill-workday-timesheet`) that have no row are the entries to propose, one per week, dated that week's Friday, notes `<Month> D-D work week`.
Propose them together with the timesheet plan when both run in one session, so a single confirmation covers both.

### Education/Coaching (course attendance)

- Types include `ImprovingU Attendance` plus prep/facilitation/instructor variants.
  `snap` the type control for the live list (each shows its own guidance).
- **Quantity** is *class hours* (a 1.5 h class → 1).
  **Notes** names the class (`<course> - <session, instructor>`).
- **Date** is the day attended.
  If unstated, find the class via Outlook (`login-microsoft-sso` app `outlook`; `snap` the week view for `<title>, <start> to <end>, <date>`) for date/duration.

## Phase 1 — Authenticate

Follow **`login-microsoft-sso`** (app `engage`) to get a logged-in Engage tab.
Run `chrome-cdp use <id>` so later commands skip `--target`.

## Phase 2 — Open the Add Activity form

Run `chrome-cdp open "$ENGAGE_ACTIVITY_URL" --json` (or `nav` in an existing tab), then `chrome-cdp wait --idle --json` (network-settle, not a fixed sleep).
**Confirm you're in by content, not URL** — Engage serves a **"Login with Improving"** view *at the activity URL* even when unauthenticated: `chrome-cdp snap --grep "Log ?in" --json`.
If a login control shows: `chrome-cdp click --by name "Login with Improving" --json`, `wait --idle`, then re-check (Phase 1 / `login-microsoft-sso` handles this).
Once the form loads, note the controls: **Activity Category**, **Activity Type**, **Date**, **Quantity**, **Notes**, submit ("Add N points").

**Skip `snap --region "Add Activity"`** — it's a heading, not a container; the filter returns only its two `StaticText` nodes, not the form.
A bare `snap` returns hundreds of unnamed layout nodes instead.
Enumerate by role instead:

```sh
for r in combobox textbox spinbutton button; do chrome-cdp snap --role "$r" --json; done
```

On client `v10.5.0`: Category/Type are **comboboxes with no accessible name** (use `--by label` in Phase 4); `Date`/`Notes` are **named textboxes**; `Quantity` is a **spinbutton named `Quantity`**; submit is `Add N points`.
`--by name` works for Date/Notes/Quantity; `--by label` is safer — it survives empty names like Category/Type's.
`chrome-cdp find "quantity" --json` locates one control without enumerating.

## Fast path — a `?guid=…` share link (skips Phases 3–4)

A `?guid=…` activity URL is a **share link**, from Engage's **`Copy Link`** button on an activity.
Opening one **prefills the whole Add Activity form** — category, type, date, quantity, notes — with the submit button already reading `Add N points`.

**The job is then to cross-verify and submit, not to fill.**
Do not re-`select` or re-`fill` populated fields, or "improve" them — the link is the source of truth.

1. Open it and authenticate as in Phases 1–2 (content-based auth applies at the guid URL too).
2. Read back **every** field with the role-enumerating `snap` from Phase 2 — confirm the form's real state, not the link's intent.
3. Check it isn't already recorded: `text --article`, scan **Current Activities** for a matching type/date/notes row.
   A share link opened twice creates a duplicate.
4. Go straight to Phase 5 (review and submit).

Treat a prefilled **Date** as intended-as-is (the day the link encodes) — the 2026-07-29 run's own answer was *"already filled, keep as it is"*.
Ask about the date only if something else in the entry contradicts it.

## Phase 3 — Gather the entry

Skip this phase and Phase 4 when the fast path above applied.

Otherwise determine each field, asking where not implied:
- **Activity** — preset name (e.g. `billed-week`, `phone-interview`) or explicit category + type; resolve a preset to its `<Category>` / `<Type>`.
- **Notes** — required free text (e.g. `"22-26 work week"`, or candidate/round).
- **Date** — default today.
- **Quantity** — default 1.

## Phase 4 — Fill the form

The whole fill is the recipe **`engage-fill-activity`** — it fills, closes the date picker, and reads back the form and the submit button's `Add N points`; it does **not** submit:

```sh
chrome-cdp recipe run engage-fill-activity --target <tab id> \
  --set category="Direct Revenue" --set type="40 Billable Hour Week" \
  --set date=08/14/2026 --set quantity=1 --set notes="August 10-14 work week"
```

Category/Type are native `<select>`s with **no accessible name**.
Address them by **visible label** via `--by label` (select's native-`<select>` sub-mode) — the steps the recipe runs:

1. **Activity Category**: `chrome-cdp select --by label "Activity Category" "<Category label>" --json`.
2. Run `chrome-cdp wait --stable --json` (Type repopulates from the category — a settle, not a fixed sleep).
   Then **Activity Type**: `chrome-cdp select --by label "Activity Type" "<Type label>" --option-match exact --json` (`--option-match exact` avoids a substring collision, e.g. `40 Billable Hour Week` vs `OVER 40 Billable Hour Week`).
3. **Date** (if not default), **Quantity**, **Notes**: set each with **`fill --by label`**, which *replaces* the existing value: `chrome-cdp fill --by label "Notes" "<value>" --json`, `chrome-cdp fill --by label "Date" "MM/DD/YYYY" --json`.
   (`--by name` also works for these three — see Phase 2 — but `--by label` holds either way.)
   - **Date shift — expect −1 day on typed dates; verify, never pre-compensate.**
     Every date typed via `fill` has stored the **previous day**: `07/10` → `7/9` (2026-07-16), `08/07` → `8/6` and `08/14` → `8/13` (2026-08-16) — six of six billed-week rows now sit on Thursdays for Friday-entered weeks (local-midnight-to-UTC).
     The one run that did **not** shift (2026-07-29) came through a `?guid=` share link, where the date arrived prefilled rather than typed.
     Still enter the date you want and read the stored row back in Phase 5: for a billed week a −1 shift stays in-week and matches the user's history, so report it rather than edit; a date that left the week is what the row's **Edit** is for.
     Tell the user the expected outcome up front (Friday entered → Thursday stored) so they can choose to enter Saturday instead.
   - A date-picker click sometimes gets ignored (only highlights); re-check and re-`fill` if unchanged.
     If a fill won't stick, check `chrome-cdp console --only-errors --json` / `chrome-cdp net --failed --json` for a thrown error vs. an ignored input.

## Phase 5 — Review and submit

- Re-`snap` (or `screenshot`): the submit button now reads **"Add N points"** — N is the points the type grants.
- Present the full entry — category, type, date, quantity, notes, **and N points** — via `AskUserQuestion`, submit recommended alongside "edit first" / "don't submit".
- Only on explicit confirmation: `chrome-cdp click --by name "Add" --match contains --role button --json` (matches "Add N points" without reading N).
- Engage submits via XHR with no toast; confirm at the request level.
  Endpoint: **`/api/services/app/Activities/CreateOrEdit`** (POST, 200), followed by two `Activities/GetAll` refreshes:

  ```sh
  chrome-cdp net --clear --json                                     # before the click
  chrome-cdp click --by name "Add" --match contains --role button --json
  chrome-cdp wait --request "Activities/CreateOrEdit" --method POST --status 2xx --json
  ```

  If the endpoint moves, re-identify it with `chrome-cdp net --xhr --json` after a submit.
- Re-run `text --article` on **Current Activities**: confirm the new row (matching category/type/date/notes) is at the top.
  **Always read back the row's Date** — this is the only way to catch a Phase 4 date shift.
- If the Date landed wrong, fix it with that row's **`Edit`** button, not delete-and-re-add.
  Report what was saved, not what was submitted.

## Removing an entry (cleanup / testing)

To delete a row (e.g. a dummy test entry) from **Current Activities**, scope the **Delete** button to that row so repeated "Delete" resolves correctly: `chrome-cdp click --by name "Delete" --in-row "<notes or type of that row>" --role button --json`.
The confirm is an **in-page** Angular **"Are you sure?"** modal, not a native dialog — `snap` surfaces it (under `alerts`); run `chrome-cdp click --by name "Yes" --role button --json`.
Add `--on-dialog accept` to the Delete click as a guard against a tenant variant's *native* confirm (a no-op for the in-page modal).
Verify the row is gone with `grid`/`eval`; don't delete a real activity in the same table.

## Safety

- Never submit ("Add N points") without the user's explicit confirmation.
- Pick category/type by accessible name, not position/index — order can change.
- Avoid actions that trigger a native browser dialog (`alert`/`confirm`); they block cdp.
  Pass `--on-dialog accept|dismiss` on such an action to avoid wedging the connection.
- If a step fails repeatedly, or a native `<select>` resists click-based selection, stop and report — don't guess.
