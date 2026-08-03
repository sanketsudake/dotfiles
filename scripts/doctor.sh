#!/usr/bin/env bash
# Health checks for the dotfiles setup. Exit non-zero if anything is wrong.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="${HARNESS_DIR:-$(cd "$REPO_DIR/.." && pwd)/harness-configs}"
FAIL=0

ok()   { printf '  ok: %s\n' "$*"; }
bad()  { printf 'FAIL: %s\n' "$*"; FAIL=1; }

echo "== tools =="
if command -v brew >/dev/null; then ok "brew $(brew --version | head -1 | awk '{print $2}')"; else bad "brew not found"; fi
if command -v stow >/dev/null; then
  stow_ver="$(stow --version | head -1 | awk '{print $NF}')"
  case "$stow_ver" in
    2.[0-3]*|1.*) bad "stow $stow_ver too old — need >= 2.4.0 for --dotfiles dir handling" ;;
    *) ok "stow $stow_ver" ;;
  esac
else
  bad "stow not found"
fi
if command -v npx >/dev/null; then ok "npx ($(command -v npx))"; else bad "npx not found (nvm node not installed? run: nvm install --lts)"; fi

echo "== brew bundle =="
if brew bundle check --file="$REPO_DIR/Brewfile" >/dev/null 2>&1; then
  ok "Brewfile satisfied"
else
  bad "Brewfile unsatisfied — run: make brew-install"
fi

echo "== symlinks =="
for target in .zshrc .zprofile .gitconfig \
              .config/git/config-personal .config/git/config-qwiet .config/git/ignore \
              .config/zsh/00-env.zsh .config/atuin/config.toml .config/btop/btop.conf \
              .config/gh/config.yml; do
  path="$HOME/$target"
  # Stow links are relative; resolve and confirm they land inside packages/.
  resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path")"
  if [ -L "$path" ] && [[ "$resolved" == "$REPO_DIR/packages/"* ]]; then
    ok "$target"
  else
    bad "$target is not a symlink into packages/ — run: make stow-link"
  fi
done

echo "== secret safety =="
for dir in .config/gh .config/git .config/zsh; do
  if [ -d "$HOME/$dir" ] && [ ! -L "$HOME/$dir" ]; then
    ok "~/$dir is a real directory"
  else
    bad "~/$dir is missing or a symlink — credentials could land in the repo (--no-folding violated)"
  fi
done
if [ -e "$HOME/.config/gh/hosts.yml" ] && [ ! -L "$HOME/.config/gh/hosts.yml" ]; then
  ok "gh hosts.yml is a plain local file"
elif [ -L "$HOME/.config/gh/hosts.yml" ]; then
  bad "gh hosts.yml is a symlink — tokens may be inside the repo"
else
  ok "gh hosts.yml absent (run gh auth login)"
fi
leaks="$(cd "$REPO_DIR" && git ls-files | grep -Ei 'hosts\.yml|\.env($|\.)|\.pem$|\.key$|token|credential' || true)"
if [ -z "$leaks" ]; then
  ok "no secret-pattern files tracked by git"
else
  bad "secret-pattern files tracked by git:"$'\n'"$leaks"
fi

echo "== harness-configs =="
if [ -d "$HARNESS_DIR/.git" ]; then
  ok "repo present at $HARNESS_DIR"
  if [ -r "$HARNESS_DIR/scripts/claude-multi-account.sh" ]; then
    ok "claude-multi-account.sh readable (sourced by ~/.config/zsh/50-harness.zsh)"
  else
    bad "claude-multi-account.sh missing"
  fi
else
  bad "harness-configs not found at $HARNESS_DIR — run: make harness-install"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then echo "doctor: all checks passed"; else echo "doctor: FAILURES above"; fi
exit "$FAIL"
