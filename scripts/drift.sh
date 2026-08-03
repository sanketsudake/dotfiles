#!/usr/bin/env bash
# Drift report: recorded configuration (Brewfile, manifests/, macos/defaults.sh)
# vs the live system, in both directions. Prints the reconcile command for every
# finding. Exit 1 if any drift; Spotlight-lagged mas entries are warnings only.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIFT=0

ok()    { printf '  ok: %s\n' "$*"; }
warn()  { printf '  warn: %s\n' "$*"; }
drift() { printf 'DRIFT: %s\n' "$*"; DRIFT=1; }

manifest_entries() { grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$1"; }

# Normalize a Brewfile-ish file to sorted "kind name" pairs. Only kinds we
# curate; brew-6 dump also emits go/npm lines, which our manifests own.
normalize_bundle() {
  awk '
    /^(tap|brew|cask|mas|vscode) / {
      kind=$1; name=$2
      gsub(/[",]/, "", name)
      print kind, name
    }
  ' "$1" | sort -u
}

echo "== brew (formulae, casks, taps, mas, vscode) =="
dump="$(mktemp)"
trap 'rm -f "$dump"' EXIT
if brew bundle dump --file="$dump" --force >/dev/null 2>&1; then
  declared="$(normalize_bundle "$REPO_DIR/Brewfile")"
  installed="$(normalize_bundle "$dump")"
  missing="$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$installed"))"
  extra="$(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$installed"))"
  # mas can't see App Store apps when the Spotlight index lags; if the app
  # bundle exists on disk, downgrade declared-but-missing mas rows to warnings.
  if [ -n "$missing" ]; then
    real_missing=""
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      kind="${row%% *}"; name="${row#* }"
      if [ "$kind" = "mas" ]; then
        app_line="$(grep -E "^mas \"[^\"]+\", id: .*$" "$REPO_DIR/Brewfile" | grep -F "$name" || true)"
        app_name="$(printf '%s' "$app_line" | sed -E 's/^mas "([^"]+)".*/\1/')"
        if [ -n "$app_name" ] && [ -d "/Applications/$app_name.app" ]; then
          warn "mas $app_name unmet only per Spotlight index; app present on disk"
          continue
        fi
      fi
      real_missing="$real_missing$row"$'\n'
    done <<< "$missing"
    missing="$(printf '%s' "$real_missing")"
  fi
  if [ -n "$missing" ]; then
    drift "declared but not installed — run: make brew-install"$'\n'"$(printf '%s\n' "$missing" | sed 's/^/    /')"
  fi
  if [ -n "$extra" ]; then
    drift "installed but not in Brewfile — add there, or brew uninstall / brew untap:"$'\n'"$(printf '%s\n' "$extra" | sed 's/^/    /')"
  fi
  [ -z "$missing" ] && [ -z "$extra" ] && ok "Brewfile matches installed state"
else
  drift "brew bundle dump failed — is brew healthy?"
fi

echo "== go tools (manifests/go-tools.txt vs ~/go/bin) =="
declared_bins="$(manifest_entries "$REPO_DIR/manifests/go-tools.txt" | while read -r mod; do
  mod="${mod%@*}"
  bin="${mod##*/}"
  case "$bin" in v[0-9]*) mod="${mod%/*}"; bin="${mod##*/}" ;; esac
  printf '%s\n' "$bin"
done | sort -u)"
installed_bins="$(ls "$HOME/go/bin" 2>/dev/null | sort -u || true)"
go_missing="$(comm -23 <(printf '%s\n' "$declared_bins") <(printf '%s\n' "$installed_bins"))"
go_extra="$(comm -13 <(printf '%s\n' "$declared_bins") <(printf '%s\n' "$installed_bins"))"
[ -n "$go_missing" ] && drift "manifest tools missing from ~/go/bin — run: make go-install"$'\n'"$(printf '%s\n' "$go_missing" | sed 's/^/    /')"
[ -n "$go_extra" ] && drift "~/go/bin binaries not in the manifest — add there, or rm ~/go/bin/<bin>:"$'\n'"$(printf '%s\n' "$go_extra" | sed 's/^/    /')"
[ -z "$go_missing" ] && [ -z "$go_extra" ] && ok "go tools match manifest"

echo "== npm globals (manifests/npm-globals.txt) =="
if command -v npm >/dev/null; then
  declared_npm="$(manifest_entries "$REPO_DIR/manifests/npm-globals.txt" | sort -u)"
  installed_npm="$(npm ls -g --depth=0 --json 2>/dev/null | jq -r '.dependencies | keys[]' 2>/dev/null | grep -vx npm | sort -u || true)"
  npm_missing="$(comm -23 <(printf '%s\n' "$declared_npm") <(printf '%s\n' "$installed_npm"))"
  npm_extra="$(comm -13 <(printf '%s\n' "$declared_npm") <(printf '%s\n' "$installed_npm"))"
  [ -n "$npm_missing" ] && drift "manifest npm globals missing — run: make npm-install"$'\n'"$(printf '%s\n' "$npm_missing" | sed 's/^/    /')"
  [ -n "$npm_extra" ] && drift "npm globals not in manifest — add there, or npm uninstall -g <pkg>:"$'\n'"$(printf '%s\n' "$npm_extra" | sed 's/^/    /')"
  [ -z "$npm_missing" ] && [ -z "$npm_extra" ] && ok "npm globals match manifest"
else
  warn "npm not on PATH — skipping (nvm not loaded in this shell?)"
fi

echo "== pipx (manifests/pipx-tools.txt) =="
if command -v pipx >/dev/null; then
  declared_pipx="$(manifest_entries "$REPO_DIR/manifests/pipx-tools.txt" | sort -u)"
  installed_pipx="$(pipx list --short 2>/dev/null | awk '{print $1}' | sort -u || true)"
  pipx_missing="$(comm -23 <(printf '%s\n' "$declared_pipx") <(printf '%s\n' "$installed_pipx"))"
  pipx_extra="$(comm -13 <(printf '%s\n' "$declared_pipx") <(printf '%s\n' "$installed_pipx"))"
  [ -n "$pipx_missing" ] && drift "manifest pipx tools missing — run: make pipx-install"$'\n'"$(printf '%s\n' "$pipx_missing" | sed 's/^/    /')"
  [ -n "$pipx_extra" ] && drift "pipx tools not in manifest — add there, or pipx uninstall <pkg>:"$'\n'"$(printf '%s\n' "$pipx_extra" | sed 's/^/    /')"
  [ -z "$pipx_missing" ] && [ -z "$pipx_extra" ] && ok "pipx tools match manifest"
else
  warn "pipx not on PATH — skipping"
fi

echo "== macOS defaults (macos/defaults.sh vs live) =="
defaults_drift=0
# Parse each `defaults [-currentHost] write <domain> <key> -<type> <value>` line
# and compare with the live value. Booleans normalize to 1/0.
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  host_flag=""
  rest="${line#defaults }"
  case "$rest" in
    -currentHost\ write\ *) host_flag="-currentHost"; rest="${rest#-currentHost write }" ;;
    write\ *) rest="${rest#write }" ;;
    *) continue ;;
  esac
  domain="${rest%% *}"; rest="${rest#* }"
  key="${rest%% *}"; rest="${rest#* }"
  rest="${rest# }"
  value="${rest#-* }"
  value="${value%\"}"; value="${value#\"}"
  case "$value" in
    true) value=1 ;;
    false) value=0 ;;
  esac
  live="$(defaults $host_flag read "$domain" "$key" 2>/dev/null || echo '<unset>')"
  if [ "$live" != "$value" ]; then
    drift "$domain $key: recorded '$value', live '$live' — update macos/defaults.sh, or run: make macos-apply"
    defaults_drift=1
  fi
done < <(grep -E '^[[:space:]]*defaults (-currentHost )?write ' "$REPO_DIR/macos/defaults.sh")
[ "$defaults_drift" -eq 0 ] && ok "recorded defaults match live values"

echo ""
if [ "$DRIFT" -eq 0 ]; then
  echo "drift: system matches recorded configuration"
else
  echo "drift: DIVERGENCES above — reconcile in whichever direction is right"
fi
exit "$DRIFT"
