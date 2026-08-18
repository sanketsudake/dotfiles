#!/usr/bin/env bash
# PreToolUse safety gate for Claude Code: a deterministic deny/ask layer that
# runs before dispatch, so the ABSOLUTE rules in claude/CLAUDE.md and
# rules/git-hygiene.md do not depend on the model reading and obeying prose.
# Mirrors the pi extensions permission-gate.ts (dangerous bash) and
# protected-paths.ts (writes to .env / .git / node_modules) for the Claude side.
#
# Every deny/ask is appended to $CLAUDE_CONFIG_DIR/safety-guard.log — a
# denied call is a signal to go find what asked for it, not only a blocked call.
#
# Wired per-profile in settings.json (not tracked in this repo):
#   {"hooks":{"PreToolUse":[
#     {"matcher":"Bash","hooks":[{"type":"command","command":"bash $CLAUDE_CONFIG_DIR/scripts/safety-guard-hook.sh","timeout":10}]},
#     {"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"bash $CLAUDE_CONFIG_DIR/scripts/safety-guard-hook.sh","timeout":10}]}
#   ]}}
#
# Decisions:
#   deny — hard block; the model gets the reason and must find another way.
#   ask  — the user is prompted (rules that say "unless explicitly asked").
# Patterns are extended regexes (grep -E). Edit the lists below, not the logic.
set -euo pipefail

# ---- Bash: deny outright -----------------------------------------------------
# W = a word boundary that also excludes - and _ (so "git-rm" or "sudoku" don't match).
# SEG = "anything up to the next ; & |" — keeps a match inside one shell command.
W='(^|[^A-Za-z0-9_-])'
SEG='([^;&|]*[[:space:]])?'
END='([[:space:]]|;|&|\||$)'
BASH_DENY=(
  "${W}sudo${END}"                                                        # privilege escalation
  "${W}(chmod|chown)[[:space:]]+${SEG}[0-7]?777${END}"                    # world-writable
  "${W}rm[[:space:]]+${SEG}(-[A-Za-z]*[rR][A-Za-z]*|--recursive)[[:space:]]+${SEG}(/|~|\\\$HOME|\\\$\\{HOME\\}|\\.git)/?\\*?[[:space:]]*(;|&|\\||\$)"  # rm -rf on / ~ $HOME .git
  "${W}git[[:space:]]+${SEG}add[[:space:]]+${SEG}(-A|--all|\\.)${END}"     # git add -A / --all / .
)

# ---- Bash: ask the user ------------------------------------------------------
BASH_ASK=(
  "${W}rm[[:space:]]+${SEG}(-[A-Za-z]*[rR][A-Za-z]*|--recursive)${END}"   # any recursive rm
  "${W}git[[:space:]]+${SEG}push[[:space:]]+${SEG}(-f|--force|--force-with-lease)${END}"  # force-push
  "${W}git[[:space:]]+${SEG}(reset[[:space:]]+${SEG}--hard|clean[[:space:]]+${SEG}-[A-Za-z]*[fF])"  # discard work
)

# ---- Edit/Write: deny these paths -------------------------------------------
# Basename .env or .env.<anything> (PATH_ALLOW carves out the committed
# example/sample/template variants); anything under .git/ or node_modules/.
PATH_DENY=(
  '(^|/)\.env(\.[^/]*)?$'
  '(^|/)\.git(/|$)'
  '(^|/)node_modules(/|$)'
)
PATH_ALLOW=(
  '(^|/)\.env\.(example|sample|template|dist)$'
)

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null || true)
log_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

emit() { # decision reason subject
  printf '%s decision=%s tool=%s reason=%s subject=%s\n' \
    "$(date +%FT%T)" "$1" "$tool" "$2" "${3:0:200}" >>"$log_dir/safety-guard.log"
  jq -cn --arg d "$1" --arg r "$2" '{hookSpecificOutput:{
    hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}'
  exit 0
}

case "$tool" in
  Bash)
    cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
    [[ -z "$cmd" ]] && exit 0
    # "git rm" is index bookkeeping, not a filesystem rm; keep it out of the rm rules.
    cmd_norm=$(sed -E 's/git[[:space:]]+rm/git-rm/g' <<<"$cmd")
    for re in "${BASH_DENY[@]}"; do
      if grep -Eq -- "$re" <<<"$cmd_norm"; then
        emit deny "safety-guard: command matches a hard-deny pattern (/$re/). See rules/git-hygiene.md and claude/CLAUDE.md." "$cmd"
      fi
    done
    for re in "${BASH_ASK[@]}"; do
      if grep -Eq -- "$re" <<<"$cmd_norm"; then
        emit ask "safety-guard: destructive or history-rewriting command; needs explicit user approval (/$re/)." "$cmd"
      fi
    done
    ;;
  Edit|Write|MultiEdit|NotebookEdit)
    path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
    [[ -z "$path" ]] && exit 0
    for re in "${PATH_ALLOW[@]}"; do
      grep -Eq -- "$re" <<<"$path" && exit 0
    done
    for re in "${PATH_DENY[@]}"; do
      if grep -Eq -- "$re" <<<"$path"; then
        emit deny "safety-guard: write to protected path blocked (/$re/): secrets and VCS/vendor internals are never edited by the agent." "$path"
      fi
    done
    ;;
esac

exit 0
