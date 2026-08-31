#!/usr/bin/env bash
# New-Mac bootstrap: Xcode CLT -> Homebrew -> clone dotfiles -> brew bundle ->
# stow links -> harness-configs -> doctor. Idempotent; every step checks first.
#
# Preferred invocation (casks may prompt for sudo, which clashes with curl|bash
# sharing stdin with the script):
#   curl -fsSL https://raw.githubusercontent.com/sanketsudake/dotfiles/main/bootstrap.sh -o /tmp/bootstrap.sh
#   bash /tmp/bootstrap.sh
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/personal/dotfiles}"
DOTFILES_SSH="git@github.com:sanketsudake/dotfiles.git"
DOTFILES_HTTPS="https://github.com/sanketsudake/dotfiles.git"

step() { printf '\n==> %s\n' "$*"; }

# Load brew into this shell from whichever prefix exists (Apple Silicon/Intel).
brew_env() {
  local p
  for p in /opt/homebrew /usr/local; do
    if [ -x "$p/bin/brew" ]; then
      eval "$("$p/bin/brew" shellenv)"
      return 0
    fi
  done
  return 1
}

step "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install
  echo "CLT install dialog opened — finish it, then re-run this script."
  exit 0
fi
echo "ok: $(xcode-select -p)"

step "Homebrew"
if ! brew_env; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew_env
fi
echo "ok: $(brew --prefix)"

step "Dotfiles repo"
# When run via curl there is no local clone yet; clone it. SSH first (keys
# usually not set up yet on a fresh machine, so fall back to https, bypassing
# any pre-existing gitconfig https->ssh rewrite).
if [ ! -d "$DOTFILES_DIR/.git" ]; then
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  git clone "$DOTFILES_SSH" "$DOTFILES_DIR" 2>/dev/null \
    || GIT_CONFIG_GLOBAL=/dev/null git clone "$DOTFILES_HTTPS" "$DOTFILES_DIR"
fi
cd "$DOTFILES_DIR"
echo "ok: $DOTFILES_DIR"

step "Brew packages (brew bundle)"
make brew-install

step "Stow links"
# Deterministic: move any pre-existing real file at a managed path aside, then
# link. End state is always the repo's configs live, originals preserved.
backup_dir="$HOME/.dotfiles-backup-$(date +%s)"
while IFS= read -r rel; do
  target="$HOME/$rel"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mkdir -p "$backup_dir/$(dirname "$rel")"
    mv "$target" "$backup_dir/$rel"
    echo "moved aside: ~/$rel -> $backup_dir/$rel"
  fi
done < <(scripts/managed-targets.sh)
make stow-link
if [ -d "$backup_dir" ]; then
  echo "!! Pre-existing files were moved to $backup_dir — port anything you need"
  echo "!! into ~/.config/zsh/90-local.zsh (gitignored), then delete the backup."
fi

step "harness-configs (AI harness setup)"
make harness-install || {
  echo "!! harness-configs setup failed (no GitHub access yet?)."
  echo "!! After 'gh auth login' / SSH keys, run: make harness-install"
}

step "Doctor"
make doctor || true

cat <<'EOF'

Bootstrap complete. Manual steps that need your credentials:
  1. gh auth login
  2. atuin login   (history sync)
  3. git lfs install
  4. Restore any machine-private ~/.ssh/config entries (host aliases, keys).
  5. Open a new terminal so zsh picks up the managed config.
EOF
