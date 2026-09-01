# nix: per-user profile (home.packages) and system tools ahead of brew.
export PATH="/run/current-system/sw/bin:$PATH"
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.codeium/windsurf/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
