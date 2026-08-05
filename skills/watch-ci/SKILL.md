---
name: watch-ci
description: >-
  Watches a PR's CI checks to terminal state in the background and turns each
  transition into a notification, instead of a foreground polling loop. Use
  when you just pushed a fix and want to know the moment a check goes green
  or red, or when the user says "watch CI", "wait for the checks", "is CI
  green yet", or "loop on CI". Pairs with debug-ci (hand back to it on a red
  check) and resolve-bot-review-threads (the
  fix→push→resolve→re-request→watch loop). Generic to any GitHub PR with an
  authenticated `gh` CLI.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Watch CI to terminal state

Arm a background monitor after a push.
It reports each check's terminal state as a notification.
Do not poll `gh pr checks` in the foreground — this wastes context and turns.

This skill works with any project.
It needs only the PR number and an authenticated `gh` CLI.

## The poll loop

```bash
prev=""
while true; do
  s=$(gh pr checks <PR> --json name,bucket,state 2>/dev/null) || { echo "gh-api-error"; sleep 30; continue; }
  cur=$(jq -r '.[] | select(.name != null) | select(.bucket != "pending") | "\(.name): \(.bucket)"' <<<"$s" | sort)
  comm -13 <(echo "$prev") <(echo "$cur")          # emit each newly-terminal check
  prev=$cur
  if jq -e 'map(select(.name != null)) | all(.bucket != "pending")' <<<"$s" >/dev/null 2>&1; then
    echo "DONE: all checks completed"
    break
  fi
  sleep 30
done
```

Run the loop in a background monitor (the harness's `Monitor` tool, or `run_in_background`).
Set a timeout that covers a full CI run — for example 40 minutes (`2400000` ms).
Each check that leaves pending state emits one stdout line.
Each line becomes one notification.
Output stays small: about one line per transition, plus a final `DONE` line.

## Discipline while a monitor is armed

Let the monitor run to completion.
Do not push new changes or re-query CI state before it finishes.
On a red check, hand the failure to the **debug-ci** skill.
