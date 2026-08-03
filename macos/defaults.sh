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

# --- apply -------------------------------------------------------------------
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
echo "Done. Keyboard repeat and appearance fully apply after re-login."
