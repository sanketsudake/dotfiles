#!/usr/bin/env bash
# Helium-only remainder of the macOS preferences script. All Apple-domain
# system defaults now live in nix/darwin/defaults.nix and apply via
# `make nix-switch`; this script keeps what nix-darwin cannot express:
# the Helium browser policy writes + Preferences JSON patch (needs Helium
# closed) and the ~/Screenshots dir. Apply with `make macos-apply`; idempotent.
set -euo pipefail

echo "Applying Helium browser defaults..."

# Screenshot target dir (the screencapture defaults live in nix, but the dir
# itself must exist).
mkdir -p "$HOME/Screenshots"

# --- helium (browser) --------------------------------------------------------
# Helium reads Chromium enterprise policy from its own preferences domain, so
# `defaults write` reaches it — no sudo, no /Library/Managed Preferences. An
# unforced write lands as level "recommended": it sets the default but Settings
# can still override it. Confirm with helium://policy after a relaunch.
# Not set here: PasswordManagerEnabled and PasswordManagerPasskeysEnabled.
# Helium's built-in HOP provider already forces both off, at a higher priority
# than any policy this file can write.
# No autofill of cards or addresses, and sites cannot probe for saved cards.
defaults write net.imput.helium AutofillCreditCardEnabled -bool false
defaults write net.imput.helium AutofillAddressEnabled -bool false
defaults write net.imput.helium PaymentMethodQueryEnabled -bool false
# No omnibox keystrokes to the search engine, and no link prefetch (2 = off).
defaults write net.imput.helium SearchSuggestEnabled -bool false
defaults write net.imput.helium NetworkPredictionOptions -int 2
# Ask where to save each download.
defaults write net.imput.helium PromptForDownloadLocation -bool true

# The new tab page's "frequently visited" tiles have no policy, so they live in
# the profile's Preferences JSON. The `shortcust` typo is Chromium's own key
# name. Helium rewrites that file when it exits, so the patch only applies while
# it is closed. Add further JSON-only keys to WANTED below.
HELIUM_PREFS="$HOME/Library/Application Support/net.imput.helium/Default/Preferences"
if [[ ! -f "$HELIUM_PREFS" ]]; then
	echo "  helium: no profile at $HELIUM_PREFS — prefs patch skipped"
elif pgrep -x Helium >/dev/null 2>&1; then
	echo "  helium: running — quit Helium and re-run to apply the prefs patch"
else
	python3 - "$HELIUM_PREFS" <<'PY'
import json, os, sys, tempfile

WANTED = {
    ("ntp", "shortcust_visible"): False,          # typo is Chromium's own key
}

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    prefs = json.load(fh)

changed = []
for (section, key), value in WANTED.items():
    block = prefs.setdefault(section, {})
    if block.get(key) != value:
        block[key] = value
        changed.append(key)

if not changed:
    print("  helium: prefs already set")
else:
    directory = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix="Preferences.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(prefs, fh, separators=(",", ":"))
        os.chmod(tmp, os.stat(path).st_mode & 0o777)
        os.replace(tmp, path)
    except BaseException:
        os.path.exists(tmp) and os.unlink(tmp)
        raise
    print("  helium: set " + ", ".join(sorted(changed)))
PY
fi

echo "Done."
