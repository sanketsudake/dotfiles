#!/usr/bin/env bash
# macOS system preferences as code, captured from the live machine on 2026-08-03.
# Only deliberately-changed settings are recorded — stock defaults are not
# restated, so Apple's defaults can evolve without this file fighting them.
# Apply with `make macos-apply`; idempotent. Grouped by domain; append new
# settings to the matching group and re-run.
set -euo pipefail

echo "Applying macOS defaults..."

# --- appearance --------------------------------------------------------------
# Dark mode (fully applies to running apps after re-login).
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

# --- finder ------------------------------------------------------------------
# List view in all Finder windows by default.
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# --- trackpad ----------------------------------------------------------------
# Tap to click (built-in + bluetooth trackpads, and the per-host mouse behavior).
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# --- apply -------------------------------------------------------------------
killall Finder 2>/dev/null || true
echo "Done. Some settings (appearance) fully apply after re-login."
