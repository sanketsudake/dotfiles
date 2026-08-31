#!/usr/bin/env bash
# Status line:
#   line 1: [Model·Effort] 📁 folder | 🌿 branch
#   line 2: bar pct | $cost | +added/-removed | $rate/hr | ⏰ elapsed | 5h% · 7d%
# Reads JSON from stdin (Claude Code statusLine hook payload).

input=$(cat)

# ---- model: strip leading "Claude " and trailing version, keep family name ----
model_raw=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')
model_short=$(printf '%s' "$model_raw" \
  | sed -E 's/^Claude *//; s/ *[0-9].*$//')
[ -z "$model_short" ] && model_short="$model_raw"

# ---- effort level (absent for models without the effort param) ----
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
effort_tag=""
case "$effort" in
  low)    effort_tag="L" ;;
  medium) effort_tag="M" ;;
  high)   effort_tag="H" ;;
  xhigh)  effort_tag="XH" ;;
  max)    effort_tag="MAX" ;;
esac

# ---- folder: basename of workspace.current_dir or cwd ----
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
folder=""
[ -n "$cwd" ] && folder=$(basename "$cwd")

# ---- git branch + dirty marker ----
branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null \
    || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null | head -n1)" ]; then
      branch="${branch}*"
    fi
  fi
fi

# ---- context usage + bar ----
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
bar=""
pct_str=""
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  filled=$(( used_int / 5 ))
  [ $filled -gt 20 ] && filled=20
  [ $filled -lt 0 ] && filled=0
  empty=$(( 20 - filled ))
  i=0; while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i+1)); done
  i=0; while [ $i -lt $empty  ]; do bar="${bar}░"; i=$((i+1)); done
  pct_str="${used_int}%"
fi

# ---- cost ----
cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')
cost_str=""
[ -n "$cost" ] && cost_str=$(awk -v c="$cost" 'BEGIN{printf "$%.2f", c}')

# ---- lines changed ----
added=$(printf '%s' "$input" | jq -r '.cost.total_lines_added // 0')
removed=$(printf '%s' "$input" | jq -r '.cost.total_lines_removed // 0')

# ---- elapsed + burn rate (total_duration_ms) ----
dur_ms=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // empty')
elapsed_str=""
rate_str=""
if [ -n "$dur_ms" ] && [ "$dur_ms" != "null" ]; then
  total_s=$(( dur_ms / 1000 ))
  h=$(( total_s / 3600 ))
  m=$(( (total_s % 3600) / 60 ))
  s=$(( total_s % 60 ))
  if   [ $h -gt 0 ]; then elapsed_str="${h}h ${m}m"
  elif [ $m -gt 0 ]; then elapsed_str="${m}m ${s}s"
  else                    elapsed_str="${s}s"
  fi
  # burn rate: only once enough signal has accumulated (>=60s elapsed, cost>0)
  if [ -n "$cost" ]; then
    rate_str=$(awk -v c="$cost" -v sec="$total_s" \
      'BEGIN{ if (sec>=60 && c>0) printf "$%.2f/hr", c*3600/sec }')
  fi
fi

# ---- rate limits (Claude.ai Pro/Max only; absent otherwise) ----
rl5=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl7=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# ---- ANSI colors ----
C_MODEL=$'\033[1;36m'   # bright cyan
C_DIM=$'\033[2;37m'     # dim
C_BAR=$'\033[0;32m'     # green
C_PCT=$'\033[0;33m'     # yellow
C_COST=$'\033[0;33m'    # yellow
C_BRANCH=$'\033[0;35m'  # magenta
C_FOLDER=$'\033[0;34m'  # blue
C_ADD=$'\033[0;32m'     # green
C_DEL=$'\033[0;31m'     # red
C_GRN=$'\033[0;32m'     # green
C_YEL=$'\033[0;33m'     # yellow
C_RED=$'\033[0;31m'     # red
C_RST=$'\033[0m'
SEP="${C_DIM} | ${C_RST}"

# threshold color for a usage percentage (green <70, yellow <90, red >=90)
rl_color() {
  if   [ "$1" -ge 90 ]; then printf '%s' "$C_RED"
  elif [ "$1" -ge 70 ]; then printf '%s' "$C_YEL"
  else                       printf '%s' "$C_GRN"
  fi
}

# ---- lines segment (omit when no edits yet) ----
lines_str=""
if [ "${added:-0}" -gt 0 ] 2>/dev/null || [ "${removed:-0}" -gt 0 ] 2>/dev/null; then
  lines_str="${C_ADD}+${added}${C_RST}/${C_DEL}-${removed}${C_RST}"
fi

# ---- rate-limit segment: 5h% · 7d%, each colored by threshold ----
rl_str=""
if [ -n "$rl5" ] || [ -n "$rl7" ]; then
  if [ -n "$rl5" ]; then
    p5=$(printf '%.0f' "$rl5")
    rl_str="${C_DIM}5h${C_RST} $(rl_color "$p5")${p5}%${C_RST}"
  fi
  if [ -n "$rl7" ]; then
    p7=$(printf '%.0f' "$rl7")
    seg="${C_DIM}7d${C_RST} $(rl_color "$p7")${p7}%${C_RST}"
    rl_str="${rl_str:+${rl_str} ${C_DIM}·${C_RST} }${seg}"
  fi
fi

# ---- line 1: [Model·Effort] 📁 folder | 🌿 branch ----
line1="${C_MODEL}[${model_short}${effort_tag:+·${effort_tag}}]${C_RST}"
[ -n "$folder" ] && line1="${line1} 📁 ${C_FOLDER}${folder}${C_RST}"
[ -n "$branch" ] && line1="${line1}${SEP}🌿 ${C_BRANCH}${branch}${C_RST}"

# ---- line 2: bar pct | $cost | +/- | $rate/hr | ⏰ elapsed | 5h · 7d ----
line2=""
if [ -n "$bar" ]; then
  line2="${C_BAR}${bar}${C_RST} ${C_PCT}${pct_str}${C_RST}"
fi
if [ -n "$cost_str" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}"
  line2="${line2}${C_COST}${cost_str}${C_RST}"
fi
if [ -n "$lines_str" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}"
  line2="${line2}${lines_str}"
fi
if [ -n "$rate_str" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}"
  line2="${line2}${C_COST}${rate_str}${C_RST}"
fi
if [ -n "$elapsed_str" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}"
  line2="${line2}⏰ ${elapsed_str}"
fi
if [ -n "$rl_str" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}"
  line2="${line2}${rl_str}"
fi

if [ -n "$line2" ]; then
  printf '%s\n%s' "$line1" "$line2"
else
  printf '%s' "$line1"
fi
