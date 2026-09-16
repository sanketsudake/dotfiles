#!/usr/bin/env bash
# Print every $HOME-relative path managed by home-manager (nix/home/), derived
# from packages/ itself so the list can never drift from reality. The harness
# packages (claude, pi, devin, copilot, agents) are excluded — they link into
# the profiles, ~/.pi, ~/.config/devin and ~/.copilot from nix/home/harness.nix,
# as out-of-store links that resolve to the repo, not into /nix/store like the
# targets checked here. The package set comes from the Makefile's HM_PACKAGES
# so the two can't diverge.
# Mapping mirrors the old stow --dotfiles layout: "dot-" path component -> ".".
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home_packages="$(sed -n 's/^HM_PACKAGES := //p' "$repo_root/Makefile")"
[ -n "$home_packages" ] || { echo "managed-targets: HM_PACKAGES not found in Makefile" >&2; exit 1; }
cd "$repo_root/packages"
# Omarchy owns btop's config (theme switcher) and has no use for the macOS-only
# bin/ helpers, so nix/home skips both there (dotfiles.omarchy); mirror that.
if [ -d /usr/share/omarchy ]; then
  home_packages="$(printf '%s\n' $home_packages | grep -vxE 'btop|bin' | tr '\n' ' ')"
fi
# shellcheck disable=SC2086
find $home_packages -mindepth 1 \( -type f -o -type l \) \
  | sed -E 's#^[^/]+/##' \
  | sed -E 's#(^|/)dot-#\1.#g' \
  | sort -u
