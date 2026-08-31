#!/usr/bin/env bash
# macOS system preferences as code, captured from the live machine (expanded 2026-08-03).
# Only deliberately-changed settings are recorded — stock defaults are not
# restated, so Apple's defaults can evolve without this file fighting them.
# Apply with `make macos-apply`; idempotent. Grouped by domain; append new
# settings to the matching group and re-run.
set -euo pipefail

echo "Applying macOS defaults..."

# --- appearance --------------------------------------------------------------
# Dark mode (fully applies to running apps after re-login).
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

# --- keyboard ----------------------------------------------------------------
# Fast key repeat (values below the Settings UI minimum; re-login to fully apply).
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Holding a key repeats it instead of opening the accent picker.
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# --- finder ------------------------------------------------------------------
# List view in all Finder windows by default.
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
# Show all filename extensions, the path bar, and the status bar.
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
# No warning when changing a file extension.
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
# Don't litter network shares and USB volumes with .DS_Store files.
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# --- screenshots -------------------------------------------------------------
# Save to ~/Screenshots (created here) without the window drop shadow.
mkdir -p "$HOME/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Screenshots"
defaults write com.apple.screencapture disable-shadow -bool true

# --- dock & spaces -----------------------------------------------------------
# Auto-hide the Dock, no recent apps section, and Spaces keep their order.
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock mru-spaces -bool false

# --- dialogs -----------------------------------------------------------------
# Save and print dialogs open expanded; new documents save locally, not iCloud.
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

# --- trackpad ----------------------------------------------------------------
# Tap to click (built-in + bluetooth trackpads, and the per-host mouse behavior).
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

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

# --- apply -------------------------------------------------------------------
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
echo "Done. Keyboard repeat and appearance fully apply after re-login."
