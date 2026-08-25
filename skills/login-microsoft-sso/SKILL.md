---
name: login-microsoft-sso
description: >-
  Ensures a browser tab is signed in to an app behind your organization's
  Microsoft (Entra) SSO (e.g. Workday, Engage, Outlook), driven by the
  `chrome-cdp` CLI on the user's real, already-logged-in browser — so it
  types no credentials.
  Use when another skill or task needs a logged-in tab before automating
  Workday, Engage, or Outlook web, or when the user runs
  /login-microsoft-sso.
  A building block for other automation skills, not a standalone task —
  invoke it first with the target app so those skills get a logged-in tab.
disable-model-invocation: true
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.1"
---

# Login to an SSO app (Microsoft-federated)

Ensure a browser tab is signed in to an app behind your organization's **Microsoft (Entra) SSO**.
Use the **`chrome-cdp`** CLI on the user's real, already signed-in browser — this skill types **no** credentials.

> See **`drive-chrome-cdp`** for CLI setup, output contract, and the passkey rule.
> Local skill, maintained in this repo (`.source.json` has `"repo": null`).

## Supported apps & config

The caller passes one app; the current set (add more in the local config):

- `workday` — Workday (My Tasks, timesheet).
- `engage` — Engage (activity/points platform).
  A fresh tab on any of its `/app/…` URLs redirects to `/account/login`; after `ENGAGE_SSO_BUTTON` it returns to the URL you asked for, so no re-`nav` is needed — `wait --url "<app host>/app"` then `wait --idle`.
- `outlook` — Outlook web (mail/calendar, Microsoft 365); no SSO button (`<APP>_SSO_BUTTON` unset) — auto-authenticates via the shared Microsoft session, so just navigate and verify.

App URLs and SSO button labels are org/tenant-specific.
They live in a never-committed local config, read at runtime: `~/.config/harness-configs/login-microsoft-sso/config` (`<APP>_HOME_URL`, `<APP>_SSO_BUTTON`).
Do not hardcode URLs or button labels.

## Steps

All commands take `--json`.
Parse the envelope and branch on the exit code (see `drive-chrome-cdp`).

1. **Connection.**
   The user's browser is **Helium**, not Google Chrome, and `doctor` reads Chrome's port file by default —
   so give it Helium's endpoint and start the daemon first (one consent prompt per session):

   ```sh
   PF="$HOME/Library/Application Support/net.imput.helium/DevToolsActivePort"
   EP="ws://127.0.0.1:$(head -1 "$PF")$(sed -n 2p "$PF")"
   chrome-cdp daemon start --endpoint "$EP" --json
   ```

   Then run `chrome-cdp doctor --json`.
   If the port file is absent, or `ok:false` (connection_failed),
   tell the user to enable `helium://inspect/#remote-debugging`, then re-run.
   Do not proceed until ready.
2. **Pick a tab.**
   Run `chrome-cdp list --url "<app host>" --json` (filters, so it skips scanning the full list).
   Reuse it: `chrome-cdp use <id>` (sticky — later commands skip `--target`).
   Record the `id` as this skill's output.
   No such tab?
   Skip to step 4 and use `open`.
3. **Config.**
   Source the config; take `<APP>_HOME_URL` and `<APP>_SSO_BUTTON` for the app.
4. **Navigate and settle.**
   Reusing a tab: `chrome-cdp nav "$HOME_URL" --json`.
   Starting fresh: `chrome-cdp open "$HOME_URL" --json` (creates the tab, navigates, makes it current — record the returned id).
   Wait for the SPA: `chrome-cdp wait --url "<expected host or path>" --timeout 15s --json` if you know it, else `chrome-cdp wait --idle --json` (prefer over a fixed `wait --for`).
5. **Check where you landed — by page content, not just the URL.**
   `chrome-cdp eval "location.href" --json` gives the host, but an SPA can render a login view at the app's own URL (e.g. Engage shows a "Login with …" button under the activity URL) — a matching URL is not proof of sign-in.
   Confirm with `chrome-cdp snap --grep "Log ?in|Sign ?in" --json`: a login/SSO control present means a sign-in page regardless of URL; its absence (or a known app control like a nav/menu) means you're in.
   - **On the app** (no login control, an app control present): done — return the tab id.
   - **On the sign-in page** (a login/SSO control present, or a vendor identity host such as a Workday `*-identity.*` domain, or an app `/account/login` page): click the app's SSO entry.
     - `chrome-cdp find "$SSO_BUTTON" --json` confirms the button's accessible name in one call (`count: 0` means absent — an answer, not an error).
     - `chrome-cdp click --by name "$SSO_BUTTON" --json` (accessible-name addressing; add `--role button` or `link` if ambiguous). Skip if the app has no SSO button (e.g. `outlook`).
     - `chrome-cdp wait --url "<app host>" --timeout 15s --json` (or `wait --idle`) — a condition, not a fixed sleep.
6. **Re-check.**
   Content over URL, again: re-run `chrome-cdp snap --grep "Log ?in|Sign ?in" --json`, then `chrome-cdp eval "location.href" --json`.
   - **Back on the app** (left the login/identity host, no login control remains): done.
   - **On Microsoft** (`login.microsoftonline.com`, or a passkey "Face, fingerprint, PIN or security key" screen): the SSO session expired.
     Stop.
     Ask the user to finish signing in manually (passkey/Touch ID), then continue once the app loads.
     Do not attempt the passkey programmatically.

## Output

The browser tab id (from `list` or `use`), signed in to the app.
Reuse it via `--target <id>` (or the sticky `use`).

## Safety

- Never type or handle credentials; the user's live session and passkey do the auth.
- If login cannot be confirmed, stop and report — do not click blindly.
- If a nav or click seems to do nothing, run `chrome-cdp console --only-errors --json` and `chrome-cdp net --failed --json` to see what failed (an SSO redirect that 4xx'd, a blocked script) before you retry.
- `click --by name` targets the control by its accessible name.
  If it stalls, re-run `find`/`snap` and retry (or `--wait ready`), not coordinates.
