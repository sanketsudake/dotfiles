---
name: remediate-codeql-alerts
description: >-
  Triages and remediates GitHub code-scanning / CodeQL alerts: lists alerts,
  traces the taint source, fixes real findings, dismisses won't-fix alerts,
  and verifies the fix on the PR merge ref. Use when fixing or triaging
  these alerts, or on triggers "fix codeql issues", "check code-scanning
  alerts", "dismiss false-positive alert". Generic to any repo with CodeQL
  enabled.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Remediate GitHub Code-Scanning / CodeQL Alerts

Work in an isolated git worktree.
Use the `superpowers:using-git-worktrees` skill if available, else `git worktree add`.

## 0. Auth Prerequisite

The `security_events` scope is required (`gh auth refresh -s security_events`).
Without it, the code-scanning API returns HTTP 403.
`public_repo` is enough for public-repo reads.

---

## 1. List Open Alerts

### Count open alerts

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts \
  --paginate \
  -q '[.[] | select(.state=="open")] | length'
```

### Full triage table (tool, rule, severity, file)

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts \
  --paginate \
  -q '.[] | select(.state=="open") | [.number, .tool.name, .rule.id, (.rule.security_severity_level // "n/a"), .most_recent_instance.location.path] | @tsv' \
  | sort -t$'\t' -k2,2 -k3,3
```

### Compact JSON per alert

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts \
  --paginate \
  -q '.[] | select(.state=="open") | {
        num:      .number,
        tool:     .tool.name,
        rule:     .rule.id,
        sev:      .rule.security_severity_level,
        file:     .most_recent_instance.location.path,
        line:     .most_recent_instance.location.start_line,
        msg:      .most_recent_instance.message.text
      }'
```

Always use `--paginate`.
Repos with more than 30 alerts need it — the default page size is 30.

### Key alert fields

| Field | Meaning |
|---|---|
| `.number` | Stable alert number — used in PATCH dismiss calls |
| `.rule.id` | Rule identifier (e.g. `go/path-injection`, `TokenPermissions`) |
| `.rule.security_severity_level` | `critical` / `high` / `medium` / `low` / null |
| `.most_recent_instance.location.{path,start_line}` | File + line of the **sink** |
| `.most_recent_instance.message.text` | Human-readable description |
| `.most_recent_instance.message.markdown` | Often contains a link to the taint **source** |
| `.tool.name` | `CodeQL`, `OSSF Scorecard`, etc. — always filter by this |

---

## 2. Inspect a Single Alert

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts/{number} \
  -q '{
        rule:   .rule.id,
        msg:    .most_recent_instance.message.text,
        path:   .most_recent_instance.location.path,
        line:   .most_recent_instance.location.start_line,
        ref:    .most_recent_instance.ref,
        commit: .most_recent_instance.commit_sha,
        analysis: .most_recent_instance.analysis_key
      }'
```

To get the full `most_recent_instance`, including `.message.markdown` (names the taint source):

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts/{number} \
  --jq '.most_recent_instance' | python3 -m json.tool | head -80
```

The `.message.markdown` field often links to the source: `"This path depends on a [user-provided value](path/to/file.go#L221C26-L221C32)."` That link is the **source**.
The alert `.location` is the **sink**.
Fix the code where the source is controlled, or add a CodeQL-recognized barrier at the sink.

### Batch-inspect multiple alerts

```bash
for n in 17 310 312 315 334 335; do
  echo "=== Alert #$n ==="
  gh api repos/{owner}/{repo}/code-scanning/alerts/$n \
    -q '{rule: .rule.id, msg: .most_recent_instance.message.text,
         path: .most_recent_instance.location.path,
         line: .most_recent_instance.location.start_line}'
done
```

---

## 3. Triage Loop

### Step 1 — group by tool first

CodeQL (data-flow taint analysis) and OSSF Scorecard (policy/configuration checks) share the same feed but need different fix strategies.
Separate them before you start work.

### Step 2 — identify the source, not just the sink

The source, not the sink, determines whether the risk is real.
Read `.message.markdown` (Section 2) to find it before you choose a fix.

### Step 3 — decide real vs false positive

**Fix in code (real finding):**
- The sink is reachable from an untrusted HTTP/network/user-supplied source.
- A custom sanitizer exists, but CodeQL does not model it as a barrier.
- Fix: replace the bare OS call at the sink with a CodeQL-recognized confinement primitive (e.g. `os.Root` for path-injection in Go, `filepath.Clean` plus a prefix check for simpler cases), or add a CodeQL custom query model.

**Dismiss (false positive / won't-fix):**
- The sink is intentionally user-supplied (e.g. an operator-configured command in a trusted channel).
- Existing mitigations are in place (no shell invocation, metacharacter rejection).
- The endpoint is an internal, trusted channel, not Internet-facing.
- No code change could clear the alert without removing the feature.

### Step 4 — fix in a git worktree

Use the `superpowers:using-git-worktrees` skill (if available) to create an isolated worktree:

```bash
git worktree add .claude/worktrees/fix-codeql-issues -b fix/codeql-{rule-slug}
```

Build, vet, lint, and test after each change:

```bash
go build ./...
go vet ./pkg/affected/...
golangci-lint run ./pkg/affected/...
go test ./pkg/affected/...
```

---

## 4. Dismiss False Positives via API

```bash
gh api -X PATCH repos/{owner}/{repo}/code-scanning/alerts/{number} \
  -f state=dismissed \
  -f dismissed_reason="won't fix" \
  -f dismissed_comment="<justification under ~280 chars>"
```

Valid `dismissed_reason` values: `"won't fix"`, `"false positive"`, `"used in tests"`.

Confirm dismissal:

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts/{number} \
  -q '{state: .state, reason: .dismissed_reason, comment: .dismissed_comment}'
```

Expected: `{"state":"dismissed","reason":"won't fix","comment":"..."}`

### Long-comment workaround

Comments longer than ~400-500 chars fail silently: state stays `open`, and the exit code may not show the error.
Keep dismiss comments under ~280 chars.
For longer justifications, pass JSON via `--input`.
See `references/dismiss-recipes.md`.

---

## 5. Open a PR

```bash
git add <changed files explicitly>
git commit -m "fix(security): <description>

Resolves CodeQL alerts #N, #M (rule: go/path-injection)."

git push -u origin fix/codeql-{rule-slug}

gh pr create \
  --base main \
  --head fix/codeql-{rule-slug} \
  --title "fix(security): <description>" \
  --body "..."
```

In the PR body, table each alert's number, rule, severity, and fix.
For dismissed false positives, record the reasoning there as an audit trail.

---

## 6. Verify Fixes Before Merge

**Do not rely only on a green CodeQL CI check.**
A green check means no *new* alerts were introduced.
It does not confirm the specific alerts you targeted are gone.
The definitive proof is querying alert instances on the PR merge ref and expecting the alert absent:

```bash
PRREF="refs/pull/{PR_NUMBER}/merge"

for n in 17 310 312 315 335 336; do
  st=$(gh api "repos/{owner}/{repo}/code-scanning/alerts/$n/instances?ref=$PRREF" \
        --jq '.[0].state' 2>/dev/null)
  echo "alert #$n -> ${st:-<no instance on this ref>}"
done
```

Expected for each fixed alert: `alert #N -> <no instance on this ref>`.
"No instance on this ref" means CodeQL analyzed the PR code and did not find the pattern.

Confirm CodeQL actually ran on the PR ref — otherwise "absent" proves nothing.
A control alert on unchanged code should still have an instance, and the analysis count should be ≥ 1:

```bash
gh api "repos/{owner}/{repo}/code-scanning/alerts/{unchanged_alert_number}/instances?ref=$PRREF" \
  --jq '.[0] | "state=\(.state)  loc=\(.location.path):\(.location.start_line)"'
gh api "repos/{owner}/{repo}/code-scanning/analyses?ref=$PRREF&tool_name=CodeQL" \
  --jq 'length'
```

---

## 7. Post-Merge State Transition

CodeQL re-runs on the default branch after merge.
Once that analysis completes, alerts absent on the PR ref transition `open` → `fixed` (with a `fixed_at` timestamp) in the security tab, automatically.
No manual action is needed.
The per-ref proof in Section 6 is the definitive evidence before the post-merge run completes.

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Treating a green CodeQL CI check as proof the alert is fixed | Query `.../instances?ref=refs/pull/{n}/merge` for each alert to confirm it is absent. |
| Fixing the sink without reading `.message.markdown` | The source (not the sink) determines the correct fix. Always read the markdown field first. |
| Mixing CodeQL and OSSF Scorecard alerts in the same fix pass | They need different strategies. Group by `.tool.name` first. |
| Long `dismissed_comment` (>~400 chars) sent as `-f` flag | State stays `open` silently. Use `--input` with a JSON file and keep the comment under ~280 chars. |
| Forgetting `--paginate` | The API returns at most 30 alerts per page; partial results look complete. Always use `--paginate`. |
| An alert stays `open` on the dashboard after merge | CodeQL has not yet re-analyzed the default branch. Wait for the post-merge CI run. |
| Using `git add -A` in the worktree | Stage specific files explicitly. |
