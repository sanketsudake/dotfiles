#!/usr/bin/env bash
# Health checks for the dotfiles setup. Exit non-zero if anything is wrong.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="${HARNESS_DIR:-$(cd "$REPO_DIR/.." && pwd)/harness-configs}"
FAIL=0

ok()   { printf '  ok: %s\n' "$*"; }
warn() { printf '  warn: %s\n' "$*"; }
bad()  { printf 'FAIL: %s\n' "$*"; FAIL=1; }

resolve() {
  realpath "$1" 2>/dev/null \
    || python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null \
    || true
}

echo "== tools =="
if command -v brew >/dev/null; then ok "brew $(brew --version | head -1 | awk '{print $2}')"; else bad "brew not found"; fi
if command -v stow >/dev/null; then
  stow_ver="$(stow --version | head -1 | awk '{print $NF}')"
  IFS=. read -r maj min _ <<< "$stow_ver"
  if [ "${maj:-0}" -gt 2 ] 2>/dev/null || { [ "${maj:-0}" -eq 2 ] && [ "${min:-0}" -ge 4 ]; } 2>/dev/null; then
    ok "stow $stow_ver"
  else
    bad "stow $stow_ver too old or unparseable — need >= 2.4.0 for --dotfiles dir handling"
  fi
else
  bad "stow not found"
fi
# npx is only needed for harness-configs' optional skills-find/vendor targets.
if command -v npx >/dev/null; then ok "npx ($(command -v npx))"; else warn "npx not found — run: nvm install --lts (needed only for harness-configs skill vendoring)"; fi

echo "== brew bundle =="
if brew bundle check --file="$REPO_DIR/Brewfile" >/dev/null 2>&1; then
  ok "Brewfile satisfied"
else
  bad "Brewfile unsatisfied — run: make brew-install"
fi

echo "== symlinks =="
# Target list is derived from packages/ (managed-targets.sh), so new packages
# are health-checked automatically.
while IFS= read -r target; do
  path="$HOME/$target"
  resolved="$(resolve "$path")"
  if [ -L "$path" ] && [[ "$resolved" == "$REPO_DIR/packages/"* ]]; then
    ok "$target"
  else
    bad "$target is not a symlink into packages/ — run: make stow-link"
  fi
done < <("$REPO_DIR/scripts/managed-targets.sh")

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
  ok "no secret-pattern filenames tracked by git"
else
  bad "secret-pattern filenames tracked by git:"$'\n'"$leaks"
fi
# Content scan: catch credential-looking values inside tracked files (e.g. a
# stow-adopted shell profile that carried exported tokens).
content_leaks="$(cd "$REPO_DIR" && git grep -nIiE "(api[_-]?key|secret|token|password)[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9_/+=-]{12,}|BEGIN [A-Z ]*PRIVATE KEY" -- packages/ 2>/dev/null || true)"
if [ -z "$content_leaks" ]; then
  ok "no credential-looking content in tracked packages/"
else
  bad "credential-looking content in tracked files:"$'\n'"$content_leaks"
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
