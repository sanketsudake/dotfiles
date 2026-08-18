#!/usr/bin/env bash
# Aggregate $CLAUDE_CONFIG_DIR/usage.jsonl (written by usage-log-hook.sh):
#   1. subagent spend by agent_type × model — is the routing table saving anything?
#   2. per-day main-session turns with cache-hit ratio — a dip after a CLAUDE.md /
#      rules / skills change is the cache-prefix invalidation ch12 warns about.
# Usage: usage-report.sh [--since DAYS] [--log FILE]...   (default: last 30 days,
#        the current profile's log). `make usage-report` runs it for every profile.
set -euo pipefail
since=30; logs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --log)   logs+=("$2"); shift 2 ;;
    *) echo "usage: $0 [--since DAYS] [--log FILE]..." >&2; exit 1 ;;
  esac
done
[[ ${#logs[@]} -gt 0 ]] || logs=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage.jsonl")

cutoff=$(date -u -v-"${since}"d +%FT%TZ 2>/dev/null || date -u -d "-${since} days" +%FT%TZ)

for log in "${logs[@]}"; do
  echo "== $log (since $cutoff)"
  if [[ ! -s "$log" ]]; then echo "   (no records)"; continue; fi
  jq -rs --arg c "$cutoff" '
    map(select(.ts >= $c)) as $r
    | ($r | map(select(.kind == "subagent"))) as $sub
    | ($r | map(select(.kind == "turn"))) as $turns
    | def k1: (.cache_read + .input + .cache_create);
      def pct(x): (x * 100 | round | tostring) + "%";
      def fmt(n): if n >= 1000000 then ((n/100000|round)/10|tostring) + "M"
                  elif n >= 1000 then ((n/100|round)/10|tostring) + "k" else (n|tostring) end;
    "-- subagents by agent_type × model (" + ($sub|length|tostring) + " runs)",
    "   runs   out-tok    ctx-tok  cache  avg-s  agent_type / model",
    ( $sub | group_by([.agent_type, (.models|join("+"))]) | map(
        { key: (.[0].agent_type // "?") + " / " + ((.[0].models|join("+")) // "?"),
          n: length, out: (map(.output)|add), ctx: (map(k1)|add),
          hit: (if (map(k1)|add) > 0 then (map(.cache_read)|add) / (map(k1)|add) else 0 end),
          dur: ((map(.duration_s)|add) / length) })
      | sort_by(-.out) | .[]
      | "   " + (.n|tostring|.[0:4]|.+"    "|.[0:6]) + (fmt(.out)|.+"          "|.[0:10]) + (fmt(.ctx)|.+"          "|.[0:10])
        + (pct(.hit)|.+"      "|.[0:6]) + ((.dur|round|tostring)|.+"      "|.[0:6]) + .key ),
    "",
    "-- main-session turns per day (" + ($turns|length|tostring) + " turns)",
    "   day         turns   out-tok    ctx-tok  cache",
    ( $turns | group_by(.ts[0:10]) | map(
        { day: .[0].ts[0:10], n: (map(.turns)|add), out: (map(.output)|add), ctx: (map(k1)|add),
          hit: (if (map(k1)|add) > 0 then (map(.cache_read)|add) / (map(k1)|add) else 0 end) })
      | .[] | "   " + .day + "  " + (.n|tostring|.+"        "|.[0:6]) + (fmt(.out)|.+"          "|.[0:10]) + (fmt(.ctx)|.+"          "|.[0:10]) + pct(.hit) ),
    ""
  ' "$log"
done
