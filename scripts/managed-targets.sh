#!/usr/bin/env bash
# Print every $HOME-relative path managed by the HOME stow packages, derived
# from packages/ itself so the list can never drift from reality. The harness
# packages (claude, pi) are excluded — they stow into the profiles and ~/.pi
# via harness-link, never into $HOME. The package set comes from the
# Makefile's HOME_PACKAGES so the two can't diverge.
# Mapping mirrors stow --dotfiles: a leading "dot-" on any path component -> ".".
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home_packages="$(sed -n 's/^HOME_PACKAGES := //p' "$repo_root/Makefile")"
[ -n "$home_packages" ] || { echo "managed-targets: HOME_PACKAGES not found in Makefile" >&2; exit 1; }
cd "$repo_root/packages"
# shellcheck disable=SC2086
find $home_packages -mindepth 1 \( -type f -o -type l \) \
  | sed -E 's#^[^/]+/##' \
  | sed -E 's#(^|/)dot-#\1.#g' \
  | sort -u
