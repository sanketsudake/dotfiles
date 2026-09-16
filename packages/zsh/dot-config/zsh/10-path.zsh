# nix: per-user profile (home.packages) and system tools ahead of brew.
export PATH="/run/current-system/sw/bin:$PATH"
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"
# Standalone home-manager (Linux hosts): user profile + its session vars.
[ -d "$HOME/.nix-profile/bin" ] && export PATH="$HOME/.nix-profile/bin:$PATH"
[ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ] \
  && . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.codeium/windsurf/bin:$PATH"
export PATH="$HOME/.npm-globals/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
