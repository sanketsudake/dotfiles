---
name: record-engage-activity
description: Use when the user wants to record an activity in Engage (the org's activity/points platform) — e.g. a billed work week, a phone interview, or an attended course/class (e.g. ImprovingU) — invoked as /record-engage-activity, with or without an Engage activity URL. Fills the Add Activity form (category, type, date, quantity, notes) and submits only after user confirmation; can derive a class's date/hours from Outlook. Also handles an Engage share link (an activity URL carrying a `?guid=…`), which arrives with the form already prefilled — then the job is to cross-verify the fields and submit, not to fill them. Drives the user's real Chrome via the chrome-cdp CLI (logs in through login-microsoft-sso).
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Record Engage Activity

Assisted, review-first automation of the Engage **Add Activity** form, driven by the **`chrome-cdp`** CLI (the user's real, logged-in Chrome).
It fills category, type, date, quantity, and notes, then **shows the entry and the points it will add, and submits only after the user confirms** — submitting writes real data and points.

> ✅ **Validated live (2026-07-16).**
> A real `billed-week` (Direct Revenue › 40 Billable Hour Week, 5 points) was recorded end-to-end: `open` + `wait --idle` → content-based auth (Engage renders "Login with Improving" at the app URL) → Category/Type are native `<select>`s with no accessible name, driven by **`select --by label`** (its native sub-mode) → `fill --by label` for Date/Notes → confirm → submit → `grid` verify.
> The date shifted a day (timezone, see Phase 4) but stayed in-week.
>
> ✅ **Validated again (2026-07-29), via a `?guid=…` share link.**
> A course attendance (Education/Coaching › ImprovingU Key Course Attendance, 2 points) was recorded through the [fast path](#fast-path--a-guid-share-link-skips-phases-34): the link opened with every field prefilled, so the run was verify → confirm → submit → verify.
> The write was confirmed by `POST /api/services/app/Activities/CreateOrEdit` → 200, then by the new top row.
> **The date did *not* shift on this run** — it saved exactly as the field held it (see Phase 4).
>
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
Only once the form is present, locate the controls: **Activity Category**, **Activity Type**, **Date**, **Quantity**, **Notes**, and the submit button ("Add N points").

**Don't reach for `snap --region "Add Activity"`** — "Add Activity" is a heading, not a container with that accessible name, so the region filter returns the two `StaticText` nodes of the heading itself and none of the form.
A bare `snap` is the opposite problem (hundreds of unnamed layout nodes).
Enumerate by role instead — that's what the controls actually are:

```sh
for r in combobox textbox spinbutton button; do chrome-cdp snap --role "$r" --json; done
```

On client `v10.5.0` that yields: Category and Type as **comboboxes with an empty accessible name** (hence `--by label` in Phase 4), `Date` and `Notes` as **named textboxes**, `Quantity` as a **spinbutton named `Quantity`**, and the submit button as `Add N points`.
So Date/Notes/Quantity *do* carry accessible names on this client and `--by name` resolves them; `--by label` also works and is the safer default, since it survives the names going empty the way Category/Type's did.
`chrome-cdp find "quantity" --json` is the quick way to re-locate a single control without enumerating.

## Fast path — a `?guid=…` share link (skips Phases 3–4)

If the user hands you an activity URL carrying a **`?guid=…`**, they are giving you a **share link**, not just the page.
Engage generates these from the **`Copy Link`** button on an activity, and opening one **prefills the whole Add Activity form** — category, type, date, quantity, and notes — with the submit button already reading the right `Add N points`.

**Then the job is to cross-verify and submit, not to fill.**
Do not re-`select` or re-`fill` fields that arrived populated, and do not "improve" them — the link is the source of truth for what the user intends to record.

1. Open it and authenticate exactly as in Phases 1–2 (the login view is served at the guid URL too, so the content-based auth check still applies).
2. Read back **every** field with the role-enumerating `snap` from Phase 2, so the confirmation you show is the form's real state rather than the link's intent.
3. Check it isn't already recorded — `text --article` and scan **Current Activities** for a row with the same type + date + notes.
   A share link can be opened twice, and Engage will happily create a duplicate.
4. Go straight to Phase 5 (review and submit).

Treat a prefilled **Date** as intended-as-is: it is the day the link encodes, and the user's own answer on the 2026-07-29 run was *"already filled, keep as it is"*.
Ask about the date only if something else in the entry contradicts it.

## Phase 3 — Gather the entry

Skip this phase and Phase 4 when the fast path above applied.

Otherwise determine, asking where not implied: **Activity** — preset name (e.g. `billed-week`, `phone-interview`) or explicit category + type, resolving a preset to its `<Category>` / `<Type>`; **Notes** — required free text (e.g. `"22-26 work week"`, or the candidate/round); **Date** — default today; **Quantity** — default 1.

## Phase 4 — Fill the form

Category/Type are native `<select>`s with **no accessible name** (their labels are separate text) — address them by their **visible label** with `--by label`, which `select` honours (its native-`<select>` sub-mode sets the option):
1. **Activity Category**: `chrome-cdp select --by label "Activity Category" "<Category label>" --json`.
2. `chrome-cdp wait --stable --json` (Type repopulates from the chosen category — a settle, not a fixed sleep), then **Activity Type**: `chrome-cdp select --by label "Activity Type" "<Type label>" --option-match exact --json` (`--option-match exact` avoids a substring collision, e.g. `40 Billable Hour Week` vs `OVER 40 Billable Hour Week`).
3. **Date** (only if not default), **Quantity**, **Notes**: set each with **`fill --by label`**, which finds the control by its visible label and, being `fill`, *replaces* the existing value rather than appending: `chrome-cdp fill --by label "Notes" "<value>" --json`, `chrome-cdp fill --by label "Date" "MM/DD/YYYY" --json`.
   (These three do carry accessible names on the current client, so `--by name` works too — see Phase 2 — but `--by label` holds either way.)
   - **Possible date shift — verify, never pre-compensate.**
     The 2026-07-16 run stored the date as the **previous day** (`07/10` → `7/9`), consistent with local midnight being converted to UTC.
     The 2026-07-29 run did **not** shift: `07/29` stored as `7/29`.
     So the shift is **not reliable**, and "helpfully" entering **target + 1** is how you land an entry on the wrong day when it doesn't apply.
     **Enter the date you actually want, then verify the saved row in Phase 5** and correct it only if it really moved.
     Beware the inverse trap too: a column of entries that all sit one day off the day you'd expect (e.g. Thursday rows for Mon–Fri weeks) is *not* proof of a shift — they may simply be what was entered.
   - A date-picker click is sometimes ignored (only highlights); re-check and re-`fill` if unchanged — and if a fill keeps not sticking, `chrome-cdp console --only-errors --json` / `chrome-cdp net --failed --json` show whether the widget threw rather than ignored you.

## Phase 5 — Review and submit

- Re-`snap` (or `screenshot`): the submit button now reads **"Add N points"** — N is the points the chosen type grants.
- Present the full entry — category, type, date, quantity, notes, **and N points** — via `AskUserQuestion`, submit recommended alongside "edit first" / "don't submit".
- Only on explicit confirmation: `chrome-cdp click --by name "Add" --match contains --role button --json` (matches "Add N points" without needing to read N first).
- Engage submits via XHR with no toast — confirm at the request level.
  The endpoint is **`/api/services/app/Activities/CreateOrEdit`** (POST, 200 on success), followed by two `Activities/GetAll` refreshes:

  ```sh
  chrome-cdp net --clear --json                                     # before the click
  chrome-cdp click --by name "Add" --match contains --role button --json
  chrome-cdp wait --request "Activities/CreateOrEdit" --method POST --status 2xx --json
  ```

  If the endpoint ever moves, re-identify it with `chrome-cdp net --xhr --json` right after a submit.
- Then re-`text --article` **Current Activities** to confirm the new row (matching category/type/date/notes) is at the top.
  **Always read back the row's Date** — this is where a Phase 4 date shift is caught, and it's the only way to know whether one happened on this run.
- If the Date did land wrong, fix it with that row's **`Edit`** button rather than deleting and re-adding.
  Report a summary of what was actually saved, not what was submitted.

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
