---
name: go-deps-security-sweep
description: >-
  Runs a grouped, bisectable Go dependency security sweep. Use when the user
  asks to upgrade outdated/vulnerable Go deps, run a dep security pass (also
  invoked as `go-deps-security-upgrade`), or process govulncheck/Dependabot
  findings. Lands one commit per logical dependency group on a dedicated
  branch so any regression is attributable and revertable. Generic to any Go
  module.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Go dependency security sweep

This playbook runs a Go dependency security upgrade.
Each dependency group lands in one commit.
This isolates failures: `git bisect` can attribute a regression to one group, then one dependency.

This procedure works with any Go module.
For the exact dependency groups and version-coupling rules, read the project's `CLAUDE.md` and `.claude/resources/`.
These list deps that must move in lockstep, any `replace`/`exclude` directives, and codegen to re-run after a bump.
Without that guidance, MVS gets these couplings wrong.

For a single dependency, skip this playbook.
Run `go get <pkg>@<ver>` and commit directly.

## Phase 0 — Baseline

1. Branch off the default branch with a **date-stamped** name: `git checkout <default> && git checkout -b deps/security-sweep-<YYYY-MM-DD>`.
   Before reuse, run `git rev-parse --verify <branch>` / `gh pr list --head <branch>` to check for a collision with a merged prior sweep.
2. Install the scanner if missing: `go install golang.org/x/vuln/cmd/govulncheck@latest`.
3. Capture the baseline: `govulncheck ./... | tee /tmp/govulncheck-before.txt`.
   Use the "affected by N vulnerabilities" line and each "Fixed in:" version as the minimum upgrade targets.
4. List outdated **direct** deps:

   ```bash
   go list -m -u -json all 2>/dev/null | python3 -c "
   import json, sys

   buf = ''
   mods = []
   for line in sys.stdin:
       buf += line
       if line.rstrip() == '}':
           try:
               mods.append(json.loads(buf))
           except Exception:
               pass
           buf = ''

   for m in mods:
       if not m.get('Indirect') and m.get('Update'):
           print(f\"{m['Path']:<70} {m['Version']:<20} -> {m['Update']['Version']}\")
   "
   ```

## Phase 1 — Group the upgrades (lowest risk first)

Group the outdated deps by ecosystem, so related modules move together.
Order groups so problems surface early; put the lowest-blast-radius group last:

1. **Platform/SDK core** (e.g. the `k8s.io/*` family) — move all to the same patch/minor; usually lowest risk on a patch bump.
2. **Framework/controller tooling** built against that core — often breaks API consumers across a minor.
3. **Observability** (e.g. all `go.opentelemetry.io/*`) — core + contrib share a version line; bump together.
4. **Transport** (`google.golang.org/grpc`, `golang.org/x/net`) — commonly paired in CVE fixes; the observability bump may already pull these up transitively, so check first.
5. **Everything else** with a CVE or minor available — lowest blast radius; leave for last.

**Lockstep groups:** some deps compile against a specific version of another — e.g. a controller framework against a platform-core minor, or anything that embeds either.
Land these as **one** commit; otherwise MVS may pick an incompatible mix.
The repo's `.claude/resources/` documents which groups are coupled — treat it as authoritative over the ordering above.

If a dep carries a CVE the baseline flagged, keep the group order but name the advisory in the commit message.

## Phase 2 — Per-group workflow

```bash
go get <pkg1>@<ver1> <pkg2>@<ver2> ...   # all deps in the group in one command
go mod tidy
go build ./pkg/... ./cmd/...              # scope away test fixtures — see pitfall
<repo lint/build/test gate>               # the project's make target, e.g. make code-checks
```

If build + gate pass, commit:
```
Bump <group name> (<pkg@ver>, <pkg@ver>)

<One-line rationale; name the GO-YYYY-NNNN advisory if this closes one.>
```

If the group fails, bisect **within** it: drop one dep at a time from the `go get`, re-run tidy+build+gate, and pin back the offender.
Commit the rest — don't skip the whole group; a partial group is still progress.

## Phase 3 — Final verification (once, after all groups)

1. `git diff <default> -- go.mod | head -80` — check the direct-deps diff matches the groups.
2. Run the repo's **full** gate (lint + tests + any build).
3. `govulncheck ./... | tee /tmp/govulncheck-after.txt`; diff against the baseline and put "CVEs closed" in the PR description.

## Pitfalls learned the hard way

- **Retracted/accidental high-version tags.**
  A transitive dep can push a bogus high tag (e.g. `v1.20.99` on a project actually on the `v0.x` line); `go get` then picks it as "latest", and `tidy` warns `retracted by module author`.
  Fix: `exclude <pkg> <bad-version>` plus an explicit `go get <pkg>@<correct-latest>`, using the repo's existing `replace`/`exclude` style.
- **`go build ./...` vs test fixtures.**
  Repos often contain `package main` fixtures with no `main` (test data); `go build ./...` fails on them even on the default branch.
  Scope the compile check to the real source trees (`./pkg/... ./cmd/...`).
- **Docker-dependent tests** (e.g. a package using `ory/dockertest`/MinIO) fail without a running daemon — environmental, not a dep regression.
  Confirm: check out `go.mod`+`go.sum` from the default branch and re-run just that package.
- **Cache/disk exhaustion after a platform-core minor bump.**
  A core bump invalidates the whole `$(go env GOCACHE)`, so the first test run recompiles everything and the cache balloons (tens of GB).
  On a near-full disk this shows as a cascade of `[build failed]` with `No space left on device`/`dsymutil failed` across unrelated packages — not a dep regression.
  Check `df -h /` and `du -sh $(go env GOCACHE)`; clear with `go clean -cache` and re-run.
- **Test output piped through `tail` hides the failing package.**
  A failing package prints `FAIL` near the end, but its name may be hundreds of lines up.
  Capture full output (`> /tmp/out.txt 2>&1`) and `grep -nE '^(FAIL|--- FAIL)'` before concluding anything.
- **`git stash pop` hazard.**
  On a clean tree, `git stash` is a silent no-op, so a later `git stash pop` can unstash a *pre-existing* WIP entry from another session and conflict.
  Run `git stash list` before any pop; recover a contaminated tree with `git checkout HEAD -- <files>`.

## Canonical outline

```
1. branch deps/security-sweep-<YYYY-MM-DD>  (check for stale merged collision first)
2. govulncheck ./... | tee /tmp/govulncheck-before.txt
3. group outdated direct deps (lowest risk first; honour the repo's lockstep groups)
4. per group: go get … ; go mod tidy ; go build ./pkg/... ./cmd/... ; <repo gate>
            on failure bisect within the group; on success commit
5. full repo gate
6. govulncheck ./... | tee /tmp/govulncheck-after.txt ; diff vs baseline
7. summarize: commits, CVEs closed, deferred groups + upstream blocker
```
