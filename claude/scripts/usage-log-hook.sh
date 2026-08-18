#!/usr/bin/env bash
# Usage/cost telemetry hook for Claude Code: turns transcripts into one JSON
# line per unit of work in $CLAUDE_CONFIG_DIR/usage.jsonl, so the routing
# table (rules/model-routing.md) is a measured saving, not an assumed one, and
# cache-hit ratio is a first-class number instead of a guess.
#
# Events (wire all three; each is one settings.json entry):
#   SubagentStop → kind=subagent : the whole subagent transcript (agent_type, model, tokens, duration)
#   Stop         → kind=turn     : the main transcript since the previous Stop (delta via a per-session offset)
#   SessionEnd   → kind=session  : totals for the whole main transcript, then the offset file is removed
#
# Wired per-profile in settings.json (not tracked in this repo):
#   {"hooks":{
#     "SubagentStop":[{"matcher":"*","hooks":[{"type":"command","command":"bash $CLAUDE_CONFIG_DIR/scripts/usage-log-hook.sh","timeout":20}]}],
#     "Stop":        [{"matcher":"*","hooks":[{"type":"command","command":"bash $CLAUDE_CONFIG_DIR/scripts/usage-log-hook.sh","timeout":20}]}],
#     "SessionEnd":  [{"matcher":"*","hooks":[{"type":"command","command":"bash $CLAUDE_CONFIG_DIR/scripts/usage-log-hook.sh","timeout":20}]}]
#   }}
#
# Record shape (one line):
#   {ts, kind, session_id, agent_id?, agent_type?, models:[..], turns, input, output,
#    cache_read, cache_create, cache_hit, duration_s, transcript}
#   cache_hit = cache_read / (input + cache_read + cache_create), 0..1
#
# Never blocks: any failure exits 0 silently. Read the log with usage-report.sh.
set -uo pipefail

input=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null || true)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null || true)
session=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || true)
[[ -n "$event" && -n "$transcript" && -f "$transcript" ]] || exit 0

log_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
log="$log_dir/usage.jsonl"
state_dir="$log_dir/usage-state"
mkdir -p "$state_dir" 2>/dev/null || exit 0

# Sum usage over transcript lines [start, end). Streaming rewrites the same
# requestId with growing usage, so keep the last record per requestId.
summarize() { # start_line
  local start="$1"
  tail -n +"$start" "$transcript" 2>/dev/null | jq -cs '
    [ .[] | select(.type == "assistant" and .message.usage != null)
      | {rid: (.requestId // .uuid // (.timestamp|tostring)), model: .message.model,
         ts: .timestamp, u: .message.usage} ]
    | group_by(.rid) | map(last)
    | { turns: length,
        models: (map(.model) | unique | map(select(. != null))),
        input:        (map(.u.input_tokens // 0) | add // 0),
        output:       (map(.u.output_tokens // 0) | add // 0),
        cache_read:   (map(.u.cache_read_input_tokens // 0) | add // 0),
        cache_create: (map(.u.cache_creation_input_tokens // 0) | add // 0),
        first_ts: (map(.ts) | map(select(. != null)) | min),
        last_ts:  (map(.ts) | map(select(. != null)) | max) }
    | .cache_hit = (if (.input + .cache_read + .cache_create) > 0
                    then ((.cache_read / (.input + .cache_read + .cache_create)) * 1000 | round / 1000) else 0 end)
    | .duration_s = (if .first_ts != null and .last_ts != null
                     then ((.last_ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
                         - (.first_ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) else 0 end)
    | del(.first_ts, .last_ts)
  ' 2>/dev/null
}

emit() { # kind summary_json extra_json
  [[ -n "$2" ]] || return 0
  jq -cn --arg ts "$(date -u +%FT%TZ)" --arg kind "$1" --arg sid "$session" --arg tp "$transcript" \
    --argjson s "$2" --argjson x "$3" \
    '{ts:$ts, kind:$kind, session_id:$sid} + $x + $s + {transcript:$tp}' >>"$log" 2>/dev/null
}

case "$event" in
  SubagentStop)
    extra=$(jq -c '{agent_id: (.agent_id // null), agent_type: (.agent_type // null)}' <<<"$input" 2>/dev/null || echo '{}')
    s=$(summarize 1); [[ "$(jq -r '.turns' <<<"$s" 2>/dev/null)" == "0" ]] && exit 0
    emit subagent "$s" "$extra"
    ;;
  Stop)
    off_file="$state_dir/$session"
    start=1; [[ -f "$off_file" ]] && start=$(<"$off_file")
    total=$(wc -l <"$transcript" | tr -d ' ')
    s=$(summarize "$start")
    echo $((total + 1)) >"$off_file"
    [[ "$(jq -r '.turns' <<<"$s" 2>/dev/null)" == "0" ]] && exit 0
    emit turn "$s" '{}'
    ;;
  SessionEnd)
    s=$(summarize 1)
    emit session "$s" "$(jq -c '{reason: (.reason // .session_end_reason // null)}' <<<"$input" 2>/dev/null || echo '{}')"
    rm -f "$state_dir/$session"
    ;;
esac
exit 0
