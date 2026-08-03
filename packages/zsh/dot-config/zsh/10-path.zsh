# HOMEBREW_PREFIX is set by brew shellenv in ~/.zprofile; fall back for odd shells.
_brew_prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
export PATH="$_brew_prefix/opt/libpq/bin:$PATH"
export PATH="$_brew_prefix/opt/openjdk/bin:$PATH"
export PATH="$_brew_prefix/opt/grep/libexec/gnubin:$PATH"
export PATH="$_brew_prefix/opt/make/libexec/gnubin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.codeium/windsurf/bin:$PATH"
unset _brew_prefix
