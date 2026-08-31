#!/usr/bin/env bash
# Print every $HOME-relative path managed by the stow packages, derived from
# packages/ itself so the list can never drift from reality.
# Mapping mirrors stow --dotfiles: a leading "dot-" on any path component -> ".".
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../packages"
find . -mindepth 2 \( -type f -o -type l \) \
  | sed -E 's#^\./[^/]+/##' \
  | sed -E 's#(^|/)dot-#\1.#g' \
  | sort -u
