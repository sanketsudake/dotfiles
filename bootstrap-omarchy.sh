#!/usr/bin/env bash
# Omarchy (Arch Linux) bootstrap: zsh via yay -> Determinate Nix -> clone
# dotfiles -> home-manager switch (CLI packages + dotfile links + harness
# links) -> vendored skills -> tools -> zsh login shell -> doctor.
# Idempotent; every step checks first. The macOS counterpart is bootstrap.sh.
#
#   curl -fsSL https://raw.githubusercontent.com/sanketsudake/dotfiles/main/bootstrap-omarchy.sh -o /tmp/bootstrap-omarchy.sh
#   bash /tmp/bootstrap-omarchy.sh
#
# The home config is selected as <user>@<hostname>; on a new machine, add a
# homeConfigurations entry (mkHomeHost + nix/hosts/<host>.nix) before running.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/personal/dotfiles}"
DOTFILES_SSH="git@github.com:sanketsudake/dotfiles.git"
DOTFILES_HTTPS="https://github.com/sanketsudake/dotfiles.git"

step() { printf '\n==> %s\n' "$*"; }

[ -r /usr/share/omarchy/default/bash/env-bootstrap ] || {
  echo "this is not an Omarchy install; on macOS use bootstrap.sh" >&2
  exit 1
}

step "Dotfiles repo"
# SSH first; fall back to https bypassing any gitconfig https->ssh rewrite.
if [ ! -d "$DOTFILES_DIR/.git" ]; then
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  git clone "$DOTFILES_SSH" "$DOTFILES_DIR" 2>/dev/null \
    || GIT_CONFIG_GLOBAL=/dev/null git clone "$DOTFILES_HTTPS" "$DOTFILES_DIR"
fi
cd "$DOTFILES_DIR"
echo "ok: $DOTFILES_DIR"

step "System packages (manifests/arch-packages.txt)"
make pacman-install

step "Determinate Nix"
if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
echo "ok: $(nix --version)"

step "Home switch (CLI packages, dotfile links, harness links)"
# home-manager moves any real file at a managed path aside as *.hm-backup
# (make nix-switch passes -b hm-backup); doctor lists the leftovers.
make nix-switch

step "AI harness (vendored skills)"
make skills-materialize || {
  echo "!! skills materialize failed (needs network). Re-run: make skills-materialize"
}

step "Tools (go/npm/pipx manifests)"
make tools-install || true

step "Login shell"
if [ "$(getent passwd "$USER" | cut -d: -f7)" != /usr/bin/zsh ]; then
  chsh -s /usr/bin/zsh
fi
echo "ok: zsh"

step "Doctor"
make doctor || true

cat <<'EOF'

Bootstrap complete. Manual steps that need your credentials:
  1. Log out and back in (login shell is now zsh).
  2. gh auth login
  3. atuin login   (history sync)
  4. git lfs install
  5. pclaude (log in), then: make plugins-sync
  6. Review any *.hm-backup files doctor listed, then delete them.
EOF
