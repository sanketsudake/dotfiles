#!/usr/bin/env bash
# PreToolUse hook on the Agent tool: logs every subagent spawn and enforces
# pinned models for named agents (see claude/rules/model-routing.md).
# Wired per-profile in settings.json:
#   {"hooks":{"PreToolUse":[{"matcher":"Agent|Task","hooks":[{"type":"command","command":"<profile>/scripts/agent-routing-hook.sh"}]}]}}
set -euo pipefail

input=$(cat)

stype=$(jq -r '.tool_input.subagent_type // "general-purpose"' <<<"$input")
model=$(jq -r '.tool_input.model // empty' <<<"$input")
desc=$(jq -r '(.tool_input.description // "") | .[0:60]' <<<"$input")

# Pins must match the model: frontmatter in claude/agents/*.md.
pin=""
case "$stype" in
  bulk-mechanic) pin="haiku" ;;
  pr-shepherd|skill-auditor) pin="sonnet" ;;
esac

log_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
printf '%s type=%s requested=%s pin=%s desc=%s\n' \
  "$(date +%FT%T)" "$stype" "${model:-frontmatter/inherit}" "${pin:-none}" "$desc" \
  >>"$log_dir/agent-routing.log"

# No explicit model param -> frontmatter pin already applies; nothing to enforce.
if [[ -z "$pin" || -z "$model" || "$model" == "$pin" ]]; then
  exit 0
fi

# Explicit override conflicts with the pin: rewrite it back deterministically.
jq -cn --argjson ti "$(jq -c --arg m "$pin" '.tool_input + {model: $m}' <<<"$input")" '
  {hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "model rewritten to pinned tier by agent-routing-hook",
    updatedInput: $ti
  }}'
