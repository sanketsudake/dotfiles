#!/usr/bin/env bash
# Project-scoped PreToolUse hook (wired in this repo's .claude/settings.json):
# when the agent runs `git commit`, run the repo's pre-flight gate first and
# block the commit (exit 2 → stderr goes back to the model) if it is stale.
# The same checks run in CI (.github/workflows/checks.yml); this catches them
# before the commit exists instead of after the push.
set -uo pipefail
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null || true)
grep -Eq '(^|[^A-Za-z0-9_-])git([[:space:]]+[^;&|]*)?[[:space:]]+commit([[:space:]]|$)' <<<"$cmd" || exit 0

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 0
out=$(make -s skills-doctor 2>&1 && make -s agents-doctor 2>&1 \
  && make -s skills-catalog CHECK=1 2>&1 && make -s suites-catalog CHECK=1 2>&1)
rc=$?
if [[ $rc -ne 0 ]]; then
  {
    echo "precommit-gate: pre-flight gate failed; fix before committing:"
    echo "$out"
    echo "(run: make skills-doctor && make agents-doctor && make skills-catalog CHECK=1 && make suites-catalog CHECK=1)"
  } >&2
  exit 2
fi
exit 0
