#!/usr/bin/env bash
# New-Mac bootstrap: Xcode CLT -> Homebrew -> Determinate Nix -> clone dotfiles
# -> darwin-rebuild switch (packages + dotfile links + macOS defaults in one
# shot) -> harness links -> tools -> doctor. Idempotent; every step checks first.
#
# Preferred invocation (sudo prompts clash with curl|bash sharing stdin):
#   curl -fsSL https://raw.githubusercontent.com/sanketsudake/dotfiles/main/bootstrap.sh -o /tmp/bootstrap.sh
#   bash /tmp/bootstrap.sh
#
# The flake pins one host config (see NIX_HOST in the Makefile). On a machine
# with a different LocalHostName, add a darwinConfigurations entry for it (or
# rename the machine) before bootstrapping.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/personal/dotfiles}"
DOTFILES_SSH="git@github.com:sanketsudake/dotfiles.git"
DOTFILES_HTTPS="https://github.com/sanketsudake/dotfiles.git"
NIX_HOST="Sankets-MacBook-Air"

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
# nix-darwin's homebrew module drives brew but does not install it.
if ! brew_env; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew_env
fi
echo "ok: $(brew --prefix)"

step "Determinate Nix"
if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
echo "ok: $(nix --version)"

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

step "System switch (packages, dotfile links, macOS defaults)"
# Move any pre-existing real file at a managed path aside so home-manager
# links cleanly. End state: the repo's configs live, originals preserved.
backup_dir="$HOME/.dotfiles-backup-$(date +%s)"
while IFS= read -r rel; do
  target="$HOME/$rel"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mkdir -p "$backup_dir/$(dirname "$rel")"
    mv "$target" "$backup_dir/$rel"
    echo "moved aside: ~/$rel -> $backup_dir/$rel"
  fi
done < <(scripts/managed-targets.sh)
# Stock /etc shell files block nix-darwin's managed copies on first switch.
for f in /etc/zshenv /etc/zprofile /etc/zshrc /etc/bashrc; do
  if [ -f "$f" ] && [ ! -L "$f" ]; then
    sudo mv "$f" "$f.before-nix-darwin"
    echo "moved aside: $f -> $f.before-nix-darwin"
  fi
done
if [ -x /run/current-system/sw/bin/darwin-rebuild ]; then
  make nix-switch
else
  # First activation: darwin-rebuild is not on the system yet; build the
  # pinned system from the flake and use its own darwin-rebuild.
  nix build "$DOTFILES_DIR#darwinConfigurations.$NIX_HOST.system"
  sudo ./result/sw/bin/darwin-rebuild switch --flake "$DOTFILES_DIR#$NIX_HOST"
fi
if [ -d "$backup_dir" ]; then
  echo "!! Pre-existing files were moved to $backup_dir — port anything you need"
  echo "!! into ~/.config/zsh/90-local.zsh (untracked local file), then delete the backup."
fi

step "AI harness (claude profiles + pi)"
make skills-materialize harness-link || {
  echo "!! harness link failed (skills materialize needs network)."
  echo "!! Re-run: make skills-materialize harness-link"
}

step "Tools (go/npm/pipx manifests)"
# npm globals are skipped with a warning until nvm's node exists.
make tools-install || true

step "Helium browser defaults"
make macos-apply || true

step "Doctor"
make doctor || true

cat <<'EOF'

Bootstrap complete. Manual steps that need your credentials:
  1. gh auth login
  2. atuin login   (history sync)
  3. git lfs install
  4. App Store sign-in, then: make nix-switch   (installs the mas apps)
  5. nvm install --lts && make npm-install
  6. Restore any machine-private ~/.ssh/config entries (host aliases, keys).
  7. Open a new terminal so zsh picks up the managed config.
EOF
