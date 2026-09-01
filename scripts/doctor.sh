#!/usr/bin/env bash
# Health checks for the dotfiles setup. Exit non-zero if anything is wrong.
set -uo pipefail

# Prefer the nix per-user profile (hooks and CI invoke this without the
# interactive shell's PATH); no-op where the profile is absent.
[ -d "/etc/profiles/per-user/$USER/bin" ] && PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
# npm globals live in a writable prefix (node is in the read-only store).
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-globals}"
PATH="$HOME/.npm-globals/bin:$PATH"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
# npx is only needed for the optional skills-find/vendor targets.
if command -v npx >/dev/null; then ok "npx ($(command -v npx))"; else warn "npx not found — run: nvm install --lts (needed only for skill vendoring)"; fi

if python3 -c 'import tomllib' 2>/dev/null; then
  ok "python3 with tomllib ($(python3 --version | awk '{print $2}'))"
else
  bad "python3 >= 3.11 with tomllib not found — sources.toml tooling needs it (brew install python)"
fi

echo "== brew bundle =="
BREWFILE="$("$REPO_DIR/scripts/nix-brewfile.sh")"
if brew bundle check --file="$BREWFILE" >/dev/null 2>&1; then
  ok "homebrew.nix satisfied"
else
  # mas relies on the Spotlight index, which can lag or go stale; if the only
  # unmet entries are App Store apps that exist on disk, that's a warning.
  unmet="$(brew bundle check --verbose --file="$BREWFILE" 2>&1 | grep '^→' || true)"
  non_mas="$(printf '%s\n' "$unmet" | grep -v '^→ App ' || true)"
  missing_apps=""
  while IFS= read -r line; do
    app="${line#→ App }"; app="${app% needs to be installed or updated.}"
    [ -d "/Applications/$app.app" ] || missing_apps="$missing_apps $app"
  done < <(printf '%s\n' "$unmet" | grep '^→ App ' || true)
  if [ -z "$non_mas" ] && [ -z "$missing_apps" ]; then
    warn "homebrew.nix mas entries unmet only per Spotlight index; all apps present on disk"
  else
    bad "homebrew.nix unsatisfied — run: make nix-switch"$'\n'"$unmet"
  fi
fi

echo "== nix =="
if [ -x /nix/var/nix/profiles/default/bin/nix ]; then
  ok "nix $(/nix/var/nix/profiles/default/bin/nix --version | awk '{print $NF}')"
else
  bad "nix not installed — run bootstrap.sh"
fi
if [ -x /run/current-system/sw/bin/darwin-rebuild ]; then
  gen="$(readlink /nix/var/nix/profiles/system | sed 's/[^0-9]*//g')"
  ok "darwin-rebuild present (system generation $gen)"
else
  bad "no active nix-darwin system — run: make nix-switch"
fi
hm_backups="$(find "$HOME" -maxdepth 3 -name '*.hm-backup' 2>/dev/null || true)"
if [ -z "$hm_backups" ]; then
  ok "no *.hm-backup files (home-manager clobbered nothing)"
else
  warn "home-manager moved real files aside — review and delete:"$'\n'"$(printf '%s\n' "$hm_backups" | sed 's/^/    /')"
fi

echo "== symlinks =="
# Target list is derived from packages/ (managed-targets.sh), so new files
# are health-checked automatically. home-manager links point into the store.
while IFS= read -r target; do
  path="$HOME/$target"
  resolved="$(resolve "$path")"
  if [ -L "$path" ] && [[ "$resolved" == /nix/store/* ]]; then
    ok "$target"
  else
    bad "$target is not a home-manager symlink into /nix/store — run: make nix-switch"
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

echo "== raycast backup =="
# Raycast config is an encrypted DB — the export (make raycast-export) is the
# only backup; keep the .rayconfig with private backups, never in the repo.
latest_ray="$(ls -t "$HOME/Documents"/*.rayconfig 2>/dev/null | head -1)"
if [ -z "$latest_ray" ]; then
  warn "no Raycast settings export in ~/Documents — run: make raycast-export"
elif [ -n "$(find "$latest_ray" -mtime +90 2>/dev/null)" ]; then
  warn "Raycast export is older than 90 days ($(basename "$latest_ray")) — run: make raycast-export"
else
  ok "Raycast export present ($(basename "$latest_ray"))"
fi

echo "== broken symlinks =="
broken="$(find "$HOME" -maxdepth 3 -type l ! -exec test -e {} \; -print 2>/dev/null || true)"
if [ -z "$broken" ]; then
  ok "no broken symlinks in ~ (depth 3)"
else
  warn "broken symlinks (stale stow links or removed targets):"$'\n'"$(printf '%s\n' "$broken" | sed 's/^/    /')"
fi

echo "== AI harness =="
if [ -r "$REPO_DIR/scripts/claude-multi-account.sh" ]; then
  ok "claude-multi-account.sh readable (sourced by ~/.config/zsh/50-harness.zsh)"
else
  bad "claude-multi-account.sh missing"
fi
for t in "$HOME/.claude-personal/CLAUDE.md" "$HOME/.claude-work/CLAUDE.md" "$HOME/.pi/skills"; do
  r="$(resolve "$t")"
  case "$r" in
    "$REPO_DIR"/*) ok "$t -> repo" ;;
    *) bad "$t does not resolve into $REPO_DIR — run: make nix-switch" ;;
  esac
done

echo ""
if [ "$FAIL" -eq 0 ]; then echo "doctor: all checks passed"; else echo "doctor: FAILURES above"; fi
exit "$FAIL"
