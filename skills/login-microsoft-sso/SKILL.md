---
name: login-microsoft-sso
description: Use to ensure an authenticated browser tab for an app behind your organization's Microsoft (Entra) SSO — e.g. Workday, Engage, Outlook — driven by the `chrome-cdp` CLI. It drives the user's real, already-logged-in Chrome, so it types no credentials; it navigates to the app and, if redirected to a sign-in page, clicks that app's SSO entry, which bounces back in via the live session. A building block for the automation skills — invoke it first (with the target app) so they operate on a logged-in tab. Invoked as /login-microsoft-sso.
disable-model-invocation: true
---

# Login to an SSO app (Microsoft-federated)

Ensure there is a Chrome tab logged in to an app that authenticates through your organization's **Microsoft (Entra) SSO**, driven by the **`chrome-cdp`** CLI.
It drives the user's real Chrome, which already holds their Microsoft session — so this skill types **no** credentials.

> Follow the **`drive-chrome-cdp`** skill for the CLI's setup, output contract, and passkey rule.
> Local skill, maintained in this repo (`.source.json` has `"repo": null`).

## Supported apps & config

The caller passes one app; the current set (add more in the local config):

- `workday` — Workday (My Tasks, timesheet).
- `engage` — Engage (activity/points platform).
- `outlook` — Outlook web (mail/calendar, Microsoft 365) — has **no** SSO button (`<APP>_SSO_BUTTON` unset) and auto-authenticates via the shared Microsoft session, so just navigate + verify.

App URLs and SSO button labels are org/tenant-specific, so they live in a never-committed local config read at runtime: `~/.config/harness-configs/login-microsoft-sso/config` (`<APP>_HOME_URL`, `<APP>_SSO_BUTTON`).
Do not hardcode URLs or button labels.

**Quote every value in that config file.** It's `source`d as shell, and SSO button labels routinely contain spaces — an unquoted value like `WORKDAY_SSO_BUTTON=Single Sign-on Login Using SSO` gets parsed as multiple shell words, which emits `command not found: Sign-on` on stderr and leaves the variable **empty**.
A downstream `click --by name "$WORKDAY_SSO_BUTTON"` then clicks by an empty name, and can silently misfire.
Always quote, as in this correct example:

```bash
WORKDAY_HOME_URL="https://wd5.myworkday.com/acme/d/home.htmld"
WORKDAY_SSO_BUTTON="Single Sign-on Login Using SSO"
ENGAGE_HOME_URL="https://engage.improving.com/"
ENGAGE_SSO_BUTTON="Login with Improving"
OUTLOOK_HOME_URL="https://outlook.office.com/mail/"
```

`outlook` needs no `_SSO_BUTTON` entry at all (see above) — don't add an empty or unquoted placeholder for it.

## Steps

All commands take `--json`; parse the envelope and branch on the exit code (see `drive-chrome-cdp`).

1. **Connection.**
   `chrome-cdp doctor --json`.
   If `ok:false` (connection_failed), tell the user to enable `chrome://inspect/#remote-debugging`, then re-run.
   Do not proceed until ready.
2. **Pick a tab.**
   `chrome-cdp list --url "<app host>" --json` (the `--url` filter finds an existing tab on the app without scanning the whole list).
   Reuse it in place and `chrome-cdp use <id>` (sticky, so later commands need no `--target`).
   Record that `id` — it is this skill's output.
   **No such tab?**
   Skip straight to a fresh one in step 4 with `open`.
3. **Config.**
   Source the config; take `<APP>_HOME_URL` and `<APP>_SSO_BUTTON` for the requested app.
4. **Navigate + settle.**
   If reusing a tab: `chrome-cdp nav "$HOME_URL" --json`.
   If starting fresh: `chrome-cdp open "$HOME_URL" --json` (creates the tab, navigates, makes it current — record the returned id).
   Then let the SPA settle: `chrome-cdp wait --url "<expected app host or path>" --timeout 15s --json` if you know the settled URL, else `chrome-cdp wait --idle --json` (network-settle — prefer over a fixed `wait --for`).
5. **Check where you landed — by PAGE CONTENT, not just the URL.**
   `chrome-cdp eval "location.href" --json` tells you the host, but an SPA can render a **login view at the app's own URL** (e.g. Engage serves a "Login with …" button under the activity URL), so a URL that looks like the app is *not* proof you're signed in.
   Confirm with a content check: `chrome-cdp snap --grep "Log ?in|Sign ?in" --json` — if a login/SSO control is present, you're on a sign-in page regardless of the URL; if it's absent (or a known app control like a nav/menu is present), you're in.
   - **On the app** (no login control, an app control present): **done — return the tab id.**
   - **On the app's sign-in page** (a login/SSO control is present, or a vendor identity host such as a Workday `*-identity.*` domain / an app `/account/login` page): click that app's SSO entry.
     - `chrome-cdp find "$SSO_BUTTON" --json` to confirm the button's exact accessible name in one ranked call (`count: 0` means it isn't on this page — an answer, not an error), then
     - `chrome-cdp click --by name "$SSO_BUTTON" --json` (accessible-name addressing — robust; add `--role button`/`link` if the name is ambiguous). If the app has **no** SSO button (e.g. `outlook`), skip the click.
     - `chrome-cdp wait --url "<app host>" --timeout 15s --json` (or `wait --idle` — a condition, not a fixed sleep).
6. **Re-check** (again, content over URL — re-`snap --grep "Log ?in|Sign ?in"` to be sure a login control is gone): `chrome-cdp eval "location.href" --json`:
   - **Back on the app** (left the login/identity host **and** no login control remains): **done.**
   - **On Microsoft** (`login.microsoftonline.com`, or a passkey "Face, fingerprint, PIN or security key" screen): the SSO session expired.
     **Stop and ask the user to finish signing in manually in that Chrome tab** (their passkey/Touch ID), then continue once the app loads.
     Do not attempt the passkey programmatically.

## Output

The Chrome tab id (from `list`/`use`) logged in to the requested app, for the calling skill to reuse via `--target <id>` (or the sticky `use`).

## Safety

- Never type or handle credentials; the user's live session and passkey do the auth.
- If login can't be confirmed, stop and report — do not click blindly.
- If a nav/click seems to do nothing, `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` show what actually failed (an SSO redirect that 4xx'd, a blocked script) before you retry.
- `click --by name` targets the control by its accessible name; if it stalls, re-run `find`/`snap` and retry (or `--wait ready`) rather than falling back to coordinates.
