---
name: source-code-for-gh-advisory
description: >-
  Fetches the exact vulnerable source tree referenced by a GitHub Security
  Advisory (GHSA-xxxx / CVE), at the last tag before the fix. Use when the
  user wants to obtain, inspect, or reproduce vulnerable source code from a
  GHSA or CVE — for security research, PoC reproduction, patch diffing, or
  auditing the affected file/function.
license: Apache-2.0
metadata:
  author: sanketsudake
  version: "1.0"
---

# Source Code For a GitHub Advisory

## Overview

A GitHub Security Advisory names the repository, version range, and often the file or function.
To analyze it locally, you need the source tree at a commit where the bug is still present, not the patched default branch.
This skill fetches advisory metadata with `gh`, picks the last vulnerable tag, and shallow-clones only that tag.

## Workflow

1. **Resolve advisory metadata with `gh`.**
   Do not scrape the HTML page.
2. **Pick the last vulnerable tag** from the version range.
3. **Shallow-clone only that tag** (`--depth 1 --branch <tag>`).
4. **Verify** the vulnerable file or symbol exists in the checkout.
5. **Report** the path, tag, and confirmed vulnerable location.

## Step 1 — Fetch advisory metadata

Use the repo-scoped endpoint first.
Fall back to the global endpoint.

```bash
GHSA="GHSA-xxxx-xxxx-xxxx"
OWNER="<owner>"; REPO="<repo>"

gh api "repos/$OWNER/$REPO/security-advisories/$GHSA" \
  || gh api "/advisories/$GHSA"
```

Extract the fields you need with `jq`:

```bash
gh api "/advisories/$GHSA" --jq '{
  repo: .repository.full_name // "<owner>/<repo>",
  summary,
  severity,
  vuln_range: .vulnerabilities[0].vulnerable_version_range,
  patched:    .vulnerabilities[0].patched_versions,
  files:      [.description | scan("`[^`]+\\.[a-zA-Z]+`")]
}'
```

Key fields:

| Field | Why it matters |
|---|---|
| `vulnerabilities[].vulnerable_version_range` | Shows which tags are affected (e.g. `>= 0.86.0, < 1.7.0`). |
| `vulnerabilities[].patched_versions` | Shows the first fixed tag. Clone the tag just below this. |
| `description` | Usually names the vulnerable file(s) and function(s). Capture them for Step 4. |
| `html_url` / `repository.full_name` | The repo to clone. |

If the advisory does not name the repo, infer it from the advisory URL the user pasted.

## Step 2 — Pick the last vulnerable tag

List tags with `gh` (no clone needed).
Pick the highest tag strictly below `patched_versions`.

```bash
gh api "repos/$OWNER/$REPO/tags" --paginate --jq '.[].name' \
  | sort -V -r | head -40
```

Rules:
- `patched_versions: 1.7.0` and range `< 1.7.0` → use `v1.6.1` (or the highest `1.6.x` tag).
- If the repo prefixes tags with `v`, keep the prefix when you clone.
- If the advisory names a specific commit, prefer that commit over a tag.

## Step 3 — Shallow-clone the single tag

Always clone only the affected tag, with depth 1.
Do not clone full history or multiple versions.

```bash
TAG="v1.6.1"
DEST="$HOME/<chosen-path>/$REPO"

git clone --depth 1 --branch "$TAG" \
  "https://github.com/$OWNER/$REPO.git" "$DEST"
```

Notes:
- `--branch` also accepts tag names.
  This lands you in detached HEAD at that tag, with one commit of history.
- To diff against the patched version later, fetch that one tag on top (still shallow):

  ```bash
  git -C "$DEST" fetch --depth 1 origin tag v1.7.0
  git -C "$DEST" diff v1.6.1 v1.7.0 -- path/to/file
  ```
- If the clone location isn't obvious from context, ask the user before creating directories under `$HOME`.

## Step 4 — Verify the vulnerable code is present

Use the file and function names captured from the advisory description.

```bash
# File exists?
ls "$DEST/<path/from/advisory>"

# Vulnerable snippet present? Match a distinctive line from the advisory.
grep -n '<distinctive-substring>' "$DEST/<path/from/advisory>"
```

If the file is missing or the snippet doesn't match, you picked the wrong tag.
Re-check `vulnerable_version_range` and try the next-lower tag.

## Step 5 — Report back

Tell the user:
- Clone path
- Tag and commit short SHA (`git -C "$DEST" rev-parse --short HEAD`)
- Confirmed vulnerable `path:line`
- Advisory id and one-line summary

## Common Mistakes

| Mistake | Fix |
|---|---|
| Cloning the default branch | The fix is already merged; the vulnerable code is gone. Always check out a tag below `patched_versions`. |
| Listing tags by cloning first | Use `gh api repos/<o>/<r>/tags` instead. No clone needed to pick the tag. |
| Guessing the affected file | The advisory description almost always names it. Parse it from `gh api` output. Don't scrape HTML. |
| Using `git checkout <tag>` after a non-tag shallow clone | Run `git fetch --depth 1 origin tag <tag>` first, or re-clone with `--branch <tag>`. |
| Ignoring CVE-only references | If the user gives a CVE, resolve it: `gh api /advisories?cve_id=CVE-YYYY-NNNNN`. |

## Red Flags

- About to run `git clone` without `--depth 1` → stop, add the flag.
- About to run `git clone` without `--branch <tag>` → stop, pick the tag first.
- Cloning more than one version "just in case" → don't.
  Fetch the second tag into the existing clone only if a diff is actually requested.
- About to `curl` the advisory HTML page → use `gh api` instead.
