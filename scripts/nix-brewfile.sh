#!/usr/bin/env bash
# Print the path of a file holding the brewfile that the nix-darwin homebrew
# module generates (nix/darwin/homebrew.nix). Consumers (doctor, drift,
# make brew-check) diff/check against this instead of the retired ./Brewfile.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIX=/nix/var/nix/profiles/default/bin/nix
HOST="$(scutil --get LocalHostName)"
OUT="${TMPDIR:-/tmp}/nix-generated-brewfile"

"$NIX" eval --raw \
  "$REPO_DIR#darwinConfigurations.$HOST.config.homebrew.brewfile" \
  >"$OUT.tmp" 2>/dev/null
mv "$OUT.tmp" "$OUT"
echo "$OUT"
