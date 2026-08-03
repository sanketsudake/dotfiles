#!/usr/bin/env bash
# macOS system preferences as code (defaults write ...).
# Phase 2 of the dotfiles revamp — settings not yet captured.
# When populated: group by domain (Dock, Finder, keyboard, trackpad, screenshots),
# make every write idempotent, and end with `killall Dock Finder SystemUIServer`
# as needed. Apply with `make macos-apply`.
set -euo pipefail

echo "macos/defaults.sh: no settings captured yet (phase 2) — nothing to apply."
