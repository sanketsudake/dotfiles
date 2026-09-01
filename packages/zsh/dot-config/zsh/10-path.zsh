# HOMEBREW_PREFIX is set by brew shellenv in ~/.zprofile; fall back for odd shells.
_brew_prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
export PATH="$_brew_prefix/opt/libpq/bin:$PATH"
export PATH="$_brew_prefix/opt/openjdk/bin:$PATH"
# nix: per-user profile (home.packages) and system tools ahead of brew.
export PATH="/run/current-system/sw/bin:$PATH"
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.codeium/windsurf/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
unset _brew_prefix
