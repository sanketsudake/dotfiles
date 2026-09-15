export DOTFILES="$HOME/personal/dotfiles"
export DOTFILES_DIR="$HOME/personal/dotfiles"

# npm globals go to a writable prefix (node itself is in the read-only nix store).
export NPM_CONFIG_PREFIX="$HOME/.npm-globals"

# Plannotator (plan/code review UI, see nix/home/plannotator.nix).
export PLANNOTATOR_BROWSER="Helium"   # macOS: `open -a Helium <url>`; also skips Glimpse
export PLANNOTATOR_SHARE="disabled"   # no share links to share.plannotator.ai / paste service
export PLANNOTATOR_REMOTE="0"         # always bind 127.0.0.1; the server has no auth (#956)
export PLANNOTATOR_AI="disabled"      # no Ask AI / review agents shelling out to `claude`
