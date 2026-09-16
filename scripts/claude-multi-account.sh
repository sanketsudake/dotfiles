# Using Multiple Claude Accounts with Claude Code
#
# Reference: https://github.com/anthropics/claude-code/issues/261#issuecomment-3071151276
#
# Claude Code uses CLAUDE_CONFIG_DIR to determine which config/profile to use.
# By setting different config directories, you can maintain separate accounts
# (e.g., personal and work) without conflicts.
#
# Add the following to your shell profile (~/.zprofile, ~/.bashrc, etc.):

# Optional request-logging proxy (github.com/sanketsudake/cc-proxy).
#
# Opt in per invocation or persistently:
#   CLAUDE_PROXY=1 pclaude        # this session goes through the proxy
#   export CLAUDE_PROXY=1         # every pclaude/wclaude goes through it
#
# When enabled, the wrapper points Claude Code at http://localhost:8787 and
# auto-starts cc-proxy if nothing is listening (install: make install in the
# cc-proxy repo, or: go install github.com/sanketsudake/cc-proxy@latest).
# Captured data lands under ~/.cc-proxy/ (markdown logs + sqlite db);
# ClickHouse/Loki can be enabled via CAP_SINK_*_ENABLED=true.
_claude_proxy_env() {
  [[ -z "$CLAUDE_PROXY" || "$CLAUDE_PROXY" == "0" ]] && return 0
  local port="${CLAUDE_PROXY_PORT:-8787}"
  if ! curl -sf -m 1 "http://localhost:$port/healthz" >/dev/null 2>&1; then
    if ! command -v cc-proxy >/dev/null 2>&1; then
      echo "cc-proxy: not installed (go install github.com/sanketsudake/cc-proxy@latest) — continuing WITHOUT proxy" >&2
      return 0
    fi
    local datadir="$HOME/.cc-proxy"
    mkdir -p "$datadir"
    (CAP_PORT="$port" \
     CAP_SINK_MARKDOWN_DIR="$datadir/logs" \
     CAP_SINK_SQLITE_PATH="$datadir/cc-proxy.db" \
     nohup cc-proxy >>"$datadir/cc-proxy.log" 2>&1 &)
    local i
    for i in {1..15}; do
      curl -sf -m 1 "http://localhost:$port/healthz" >/dev/null 2>&1 && break
      sleep 0.2
    done
    if curl -sf -m 1 "http://localhost:$port/healthz" >/dev/null 2>&1; then
      echo "cc-proxy: started on :$port (data: $datadir)" >&2
    else
      echo "cc-proxy: failed to start (see $datadir/cc-proxy.log) — continuing WITHOUT proxy" >&2
      return 0
    fi
  fi
  export ANTHROPIC_BASE_URL="http://localhost:$port"
}

_claude_with_profile() {
  export CLAUDE_CONFIG_DIR="$1"
  _claude_proxy_env
  command claude "${@:2}"
}

# Personal profile
pclaude() {
  _claude_with_profile "$HOME/.claude-personal" "$@"
}

# Work profile
wclaude() {
  _claude_with_profile "$HOME/.claude-work" "$@"
}

# Prompt to choose profile when invoking plain `claude`; a machine with only
# the personal profile (no ~/.claude-work) goes straight to pclaude.
claude() {
  if [[ ! -d "$HOME/.claude-work" ]]; then
    pclaude "$@"
    return
  fi
  echo "Which Claude account do you want to use?"
  echo "  1) pclaude (Personal)"
  echo "  2) wclaude (Work)"
  read -r "choice?Select [1/2]: "
  case "$choice" in
    1|p) pclaude "$@" ;;
    2|w) wclaude "$@" ;;
    *) echo "Invalid choice. Aborting." ; return 1 ;;
  esac
}

# Usage:
#   pclaude                  # Launch with personal account
#   wclaude                  # Launch with work account
#   claude                   # Prompts you to pick an account
#   pclaude --resume         # Resume last session with personal account
#   CLAUDE_PROXY=1 pclaude   # Personal account through cc-proxy (request logging)
#   CLAUDE_PROXY=1 wclaude   # Work account through cc-proxy
