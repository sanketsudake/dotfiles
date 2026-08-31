# PR Shepherding

> Get a pull request from pushed to merged: clean diff, green CI, resolved reviews.

There's a loop every PR goes through between "I pushed" and "it merged," and most of it is busywork an agent can carry for you.
This suite covers that loop end to end: make the PR easy to review before anyone looks at it, strip out AI-generated slop from the diff, watch CI to a terminal state instead of polling `gh pr checks` in a loop, triage a red check to the failing line cheaply, and clear bot review threads so the PR stays at a mergeable baseline.
Push once, then let the agent shepherd it — fixing what's red, resolving what's flagged, and re-requesting review — until it's ready to merge.

## How it works

```mermaid
flowchart TB
    tidy["tidy commits"] -->|"<b>1.</b> tidy commits"| clean["strip AI slop"]
    clean -->|"<b>2.</b> clean diff"| push["push"]
    push -->|"<b>3.</b> push"| watch["watch CI"]
    push -.->|"parallel track"| threads["bot review threads"]
    watch -->|"<b>4.</b> check state"| red{"red check?"}
    red -->|"<b>5.</b> red"| debug["debug failure"]
    debug -->|"<b>6.</b> fix & push"| push
    red -->|"<b>7.</b> green"| merge["ready to merge"]
    threads -->|"resolved"| merge
    classDef leader fill:#10b981,stroke:#047857,color:#fff
    classDef process fill:#38bdf8,stroke:#0369a1,color:#fff
    classDef resource fill:#fb7185,stroke:#be123c,color:#fff
    classDef standby fill:#94a3b8,stroke:#475569,color:#fff
    class push leader
    class tidy,clean,watch,red,debug process
    class threads resource
    class merge standby
```

Before the first push, the diff gets tidied and de-slopped.
After that, `push` is the hub: it kicks off CI watching and, in parallel, bot review-thread resolution.
A red check sends you to `debug-ci` and back to `push`; a green check plus resolved threads is what "ready to merge" means.

## A week with it

Each step is the literal phrase you say to your agent (Claude Code, pi, or any harness that reads skills):

1. **"make this easy to review"** — clean up noisy commit history, tighten the PR description, and add reviewer guidance without touching behavior (`make-pr-easy-to-review`).
2. **"deslop this diff"** — remove AI-generated code slop and style noise from the branch before anyone reviews it (`deslop`).
3. **"resolve copilot comments"** — fix what a bot reviewer flagged, mark the threads resolved, and re-request review (`resolve-bot-review-threads`).
4. **"watch CI"** — arm a background watch on the PR's checks and get notified the moment one goes green or red, instead of polling (`watch-ci`).
5. **"why is this failing in CI"** — triage a red check to the failing line, cheapest log fetch first, separating real regressions from pre-existing noise (`debug-ci`).

<!-- suite-skills:begin -->
## Skills in this suite

| Skill | Purpose |
|-------|---------|
| [`make-pr-easy-to-review`](https://github.com/cursor/plugins/tree/bdf7aa355337897f167153e05069aca505dae17c/cursor-team-kit/skills/make-pr-easy-to-review) | Prepare PRs for review by cleaning noisy history, improving PR descriptions, and adding reviewer guidance without changing code behavior. |
| [`deslop`](https://github.com/cursor/plugins/tree/bdf7aa355337897f167153e05069aca505dae17c/cursor-team-kit/skills/deslop) | Remove AI-generated code slop and clean up code style |
| [`resolve-bot-review-threads`](../../skills/resolve-bot-review-threads/SKILL.md) | Clears bot/Copilot review threads on a PR — fixes the issues, marks threads resolved via GraphQL, and re-requests the bot until the PR is clean. |
| [`watch-ci`](../../skills/watch-ci/SKILL.md) | Watches a PR's CI checks to terminal state in the background and turns each transition into a notification, instead of a foreground polling loop. |
| [`debug-ci`](../../skills/debug-ci/SKILL.md) | Triages and root-causes a failing GitHub Actions CI run on a PR by separating real regressions from pre-existing noise and escalating log fetches cheapest-fi... |

## Install

With the [skills.sh](https://www.skills.sh/) CLI (needs Node.js):

```bash
npx skills add sanketsudake/harness-configs \
  --skill make-pr-easy-to-review \
  --skill deslop \
  --skill resolve-bot-review-threads \
  --skill watch-ci \
  --skill debug-ci \
  -y
```
<!-- suite-skills:end -->

## Getting started

1. Install the skills (block above).
2. Make sure `gh auth status` shows a token with `repo` scope — `resolve-bot-review-threads` needs the GraphQL API to resolve threads and re-request bot reviewers, and `watch-ci` / `debug-ci` both shell out to `gh pr checks` / `gh run view`.
3. Push a branch, open the PR, and say **"make this easy to review"** to kick off the loop; from there, watch and debug take over until it's green.

---

Part of [harness-configs](../../README.md); browse all skills in the [catalog](../../skills/README.md).
