#!/usr/bin/env bash
# skills-scan.sh — security-scan skills with NVIDIA SkillSpector
# (https://github.com/NVIDIA/skillspector): prompt injection, exfiltration,
# privilege escalation, supply chain, excessive agency, dangerous code, …
#
# Usage:
#   skills-scan.sh [--name NAME]... [--path DIR] [--llm] [--show-suppressed]
#                  [--fail-at SCORE] [--report FILE] [--quiet]
#
#   default        scan every skill under skills/ (authored + materialized vendored)
#   --name NAME    scan only skills/NAME (repeatable)
#   --path DIR     scan an arbitrary skill directory (used by the fetch/update gate)
#   --llm          add SkillSpector's LLM semantic pass via the local `claude` CLI
#                  (SKILLSPECTOR_PROVIDER=claude_cli); default is static-only
#   --fail-at N    fail when a skill's residual risk score is >= N (default 50)
#   --report FILE  write the combined JSON report (default: scratch, discarded)
#
# Baselines (accepted findings, each with a reason) live in
# security/skillspector/: _global.json applies to every skill, <name>.json to one.
# They are JSON in SkillSpector's baseline schema (version 2, glob `rules`);
# the script merges global + per-skill into the baseline handed to the scanner.
# Exit 1 when any skill fails: a residual HIGH/CRITICAL finding, or score >= --fail-at.
# Exit 3 when skillspector is not installed:  uv tool install git+https://github.com/NVIDIA/skillspector.git
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
BASELINE_DIR="$REPO_ROOT/security/skillspector"
names=(); path=""; llm=0; show=0; fail_at=50; report=""; quiet=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) names+=("$2"); shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --llm) llm=1; shift ;;
    --show-suppressed) show=1; shift ;;
    --fail-at) fail_at="$2"; shift 2 ;;
    --report) report="$2"; shift 2 ;;
    --quiet) quiet=1; shift ;;
    *) echo "usage: see header of $0" >&2; exit 2 ;;
  esac
done
command -v skillspector >/dev/null 2>&1 || {
  echo "skills-scan: skillspector not installed — uv tool install git+https://github.com/NVIDIA/skillspector.git" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "skills-scan: jq required" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export_dir="$tmp/skills"; mkdir -p "$export_dir" "$tmp/reports"

# Export what would actually be installed: skill dirs minus local build/cache
# artifacts (they are gitignored, but a scan of the live tree would flag them).
export_skill() { # src name
  rsync -a --exclude '__pycache__/' --exclude '*.pyc' --exclude '.DS_Store' \
    --exclude 'node_modules/' --exclude '.venv/' --exclude 'bin/' \
    "$1/" "$export_dir/$2/"
}
targets=()
if [[ -n "$path" ]]; then
  [[ -f "$path/SKILL.md" ]] || { echo "skills-scan: $path has no SKILL.md" >&2; exit 2; }
  n="$(basename "$path")"; export_skill "$path" "$n"; targets+=("$n")
elif [[ ${#names[@]} -gt 0 ]]; then
  for n in "${names[@]}"; do
    [[ -f "$SKILLS_DIR/$n/SKILL.md" ]] || { echo "skills-scan: skills/$n has no SKILL.md (not materialized?)" >&2; exit 2; }
    export_skill "$SKILLS_DIR/$n" "$n"; targets+=("$n")
  done
else
  for d in "$SKILLS_DIR"/*/; do
    n="$(basename "$d")"; [[ -f "$d/SKILL.md" ]] || continue
    export_skill "$d" "$n"; targets+=("$n")
  done
fi

# Merge global + per-skill baselines into one file the scanner accepts.
baseline_for() { # name -> file path or ""
  local g="$BASELINE_DIR/_global.json" s="$BASELINE_DIR/$1.json" out="$tmp/baseline-$1.json"
  [[ -f "$g" || -f "$s" ]] || { echo ""; return; }
  jq -s '{version: 2,
          rules: ([.[] | .rules // []] | add),
          fingerprints: ([.[] | .fingerprints // []] | add)}' \
    $( [[ -f "$g" ]] && echo "$g" ) $( [[ -f "$s" ]] && echo "$s" ) > "$out"
  echo "$out"
}

env_llm=()
if [[ "$llm" -eq 1 ]]; then env_llm=(env SKILLSPECTOR_PROVIDER=claude_cli); llm_flag=(); else llm_flag=(--no-llm); fi
show_flag=(); [[ "$show" -eq 1 ]] && show_flag=(--show-suppressed)
jobs="${SKILLS_SCAN_JOBS:-$( (sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4) )}"

# One scanner process per skill (SkillSpector's own scoring/baseline per skill),
# run in parallel — a non-zero exit is the scanner's verdict, not an error, as
# long as the JSON report was written.
scan_one() { # name
  local n="$1" bl out
  bl="$(baseline_for "$n")"
  local bl_flag=(); [[ -n "$bl" ]] && bl_flag=(--baseline "$bl")
  out="$tmp/reports/$n.json"
  "${env_llm[@]}" skillspector scan "$export_dir/$n" "${llm_flag[@]}" "${bl_flag[@]}" "${show_flag[@]}" \
      --format json --output "$out" >"$tmp/reports/$n.log" 2>&1 || true
  [[ -s "$out" ]] && jq -e '.risk_assessment' "$out" >/dev/null 2>&1 || echo "$n" >>"$tmp/errors"
}
export -f scan_one baseline_for
export tmp export_dir BASELINE_DIR
export env_llm_str="${env_llm[*]:-}" llm_flag_str="${llm_flag[*]:-}" show_flag_str="${show_flag[*]:-}"
# bash -c re-hydrates the arrays exported as strings above.
printf '%s\n' "${targets[@]}" | xargs -P "$jobs" -I{} bash -c '
  env_llm=($env_llm_str); llm_flag=($llm_flag_str); show_flag=($show_flag_str); scan_one "$1"' _ {}

fail=0; rows=""
if [[ -f "$tmp/errors" ]]; then
  fail=1
  while IFS= read -r n; do echo "skills-scan: scanner error on $n:"; tail -5 "$tmp/reports/$n.log"; done <"$tmp/errors"
fi
for n in "${targets[@]}"; do
  out="$tmp/reports/$n.json"; [[ -s "$out" ]] || continue
  score=$(jq -r '.risk_assessment.score // 0' "$out")
  sev=$(jq -r '.risk_assessment.severity // "?"' "$out")
  active=$(jq -r '.issues | length' "$out")
  high=$(jq -r '[.issues[] | select(.severity=="HIGH" or .severity=="CRITICAL")] | length' "$out")
  supp=$(jq -r '.suppressed_count // 0' "$out")
  status=ok
  if [[ "$high" -gt 0 || "$score" -ge "$fail_at" ]]; then status=FAIL; fail=1; fi
  rows+="$status"$'\t'"$score"$'\t'"$sev"$'\t'"$active"$'\t'"$high"$'\t'"$supp"$'\t'"$n"$'\n'
  if [[ "$status" == FAIL || ( "$quiet" -eq 0 && "$active" -gt 0 ) ]]; then
    jq -r --arg n "$n" '.issues[] | "    " + $n + ": [" + .severity + "] " + (.id|tostring) + " " + .category
        + " @ " + (.location.file|tostring) + (if .location.start_line then ":" + (.location.start_line|tostring) else "" end)
        + " — " + ((.finding // .explanation // "")|gsub("\n";" ")|.[0:140])' "$out"
  fi
  if [[ "$show" -eq 1 ]]; then
    jq -r --arg n "$n" '.suppressed[]? | "    " + $n + ": (suppressed) " + (.id|tostring) + " " + .category + " @ " + (.location.file|tostring)' "$out"
  fi
done

printf '%-5s %5s  %-8s %6s %5s %5s  %s\n' status score severity active high supp skill
printf '%s' "$rows" | sort -k2,2rn | awk -F'\t' '{ printf "%-5s %5s  %-8s %6s %5s %5s  %s\n", $1,$2,$3,$4,$5,$6,$7 }'
[[ -n "$report" ]] && jq -s '{skill_count: length, skills: .}' "$tmp"/reports/*.json > "$report" && echo "report: $report"

if [[ "$fail" -ne 0 ]]; then
  echo "skills-scan: FAIL — a residual HIGH/CRITICAL finding or score >= $fail_at (fix it, or accept it with a reason in $(realpath --relative-to="$REPO_ROOT" "$BASELINE_DIR" 2>/dev/null || echo security/skillspector)/<name>.json)" >&2
  exit 1
fi
echo "skills-scan: all ${#targets[@]} skill(s) pass"
