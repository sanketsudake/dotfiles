#!/usr/bin/env bash
# New-Mac bootstrap: Xcode CLT -> Homebrew -> clone dotfiles -> brew bundle ->
# stow links -> harness-configs -> doctor. Idempotent; every step checks first.
#
#   curl -fsSL https://raw.githubusercontent.com/sanketsudake/dotfiles/master/bootstrap.sh | bash
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/personal/dotfiles}"
DOTFILES_SSH="git@github.com:sanketsudake/dotfiles.git"
DOTFILES_HTTPS="https://github.com/sanketsudake/dotfiles.git"

step() { printf '\n==> %s\n' "$*"; }

step "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install
  echo "CLT install dialog opened — finish it, then re-run this script."
  exit 0
fi
echo "ok: $(xcode-select -p)"

step "Homebrew"
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
echo "ok: $(brew --prefix)"

step "Dotfiles repo"
# When piped via curl there is no local clone yet; clone it. SSH first (keys
# usually not set up yet on a fresh machine, so fall back to https).
if [ ! -d "$DOTFILES_DIR/.git" ]; then
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  git clone "$DOTFILES_SSH" "$DOTFILES_DIR" 2>/dev/null \
    || git clone "$DOTFILES_HTTPS" "$DOTFILES_DIR"
fi
cd "$DOTFILES_DIR"
echo "ok: $DOTFILES_DIR"

step "Brew packages (brew bundle)"
make brew-install

step "Stow links"
# First run on a machine with pre-existing real dotfiles: adopt absorbs them
# into the working tree so stow can link, then the diff MUST be reviewed.
if [ -e "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
  make stow-adopt
  echo ""
  echo "!! Pre-existing dotfiles were adopted into the repo working tree."
  echo "!! Review with: git -C $DOTFILES_DIR diff"
  echo "!! Restore the repo versions with: git -C $DOTFILES_DIR checkout -- packages/"
else
  make stow-link
fi

step "harness-configs (AI harness setup)"
make harness-install

step "Doctor"
make doctor || true

cat <<'EOF'

Bootstrap complete. Manual steps that need your credentials:
  1. gh auth login
  2. atuin login   (history sync)
  3. git lfs install
  4. Open a new terminal so zsh picks up the managed config.
EOF
