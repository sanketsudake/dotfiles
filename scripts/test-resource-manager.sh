#!/usr/bin/env bash
# Smoke test for scripts/resource-manager.sh: fetch → materialize → doctor →
# delete round-trip for one small vendored skill. Runs in a throwaway clone
# of this repo so it never mutates the working tree. Needs network + jq.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone --quiet "$REPO_ROOT" "$tmp/repo"
# Test the tooling as it is on disk (uncommitted edits included), not the last commit.
cp "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/scripts/*.py "$tmp/repo/scripts/"
cp "$REPO_ROOT/Makefile" "$tmp/repo/Makefile"
cp "$REPO_ROOT/sources.toml" "$tmp/repo/sources.toml"
cd "$tmp/repo"
git add scripts Makefile sources.toml
git -c user.email=ci@example.invalid -c user.name=ci commit -qm "working-tree tooling" || true
# Absorb catalog-wording drift the working-tree tooling may carry, so the
# final clean-tree assertion checks only the round-trip's own effects.
make -s skills-catalog >/dev/null 2>&1 || true
git -c user.email=ci@example.invalid -c user.name=ci commit -qam "working-tree catalog" || true

# Hermetic upstream: a local git repo holding one small skill, so the test
# never depends on a third party's default branch (a rename there must not red CI).
UPSTREAM="$tmp/upstream"
mkdir -p "$UPSTREAM/skills/ci-smoke"
cat > "$UPSTREAM/skills/ci-smoke/SKILL.md" <<'SKILL'
---
name: ci-smoke
description: Smoke-test fixture for resource-manager.sh; does nothing. Use never.
license: Apache-2.0
metadata:
  author: ci
  version: "1.0"
---

# ci-smoke

A fixture. It has no behaviour.
SKILL
git -C "$UPSTREAM" init -q -b main
git -C "$UPSTREAM" -c user.email=ci@example.invalid -c user.name=ci add -A
git -C "$UPSTREAM" -c user.email=ci@example.invalid -c user.name=ci commit -qm "fixture"
REPO="file://$UPSTREAM" SUBPATH=skills/ci-smoke NAME=ci-smoke
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== fetch"
make -s skills-fetch REPO=$REPO SUBPATH=$SUBPATH NAME=$NAME CATEGORY=ci-smoke
manifest_json() { python3 scripts/toml-manifest.py to-json sources.toml; }
commit=$(manifest_json | jq -re --arg n "$NAME" '.skill[]|select(.name==$n)|.commit') || fail "no manifest entry"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || fail "manifest commit is not a sha: $commit"
grep -qx "/skills/$NAME/" .gitignore || fail ".gitignore line missing"
[[ -f skills/$NAME/SKILL.md ]] || fail "SKILL.md not fetched"
[[ "$(jq -r .commit skills/$NAME/.source.json)" == "$commit" ]] || fail "sidecar commit != manifest commit"
[[ -z "$(git status --porcelain -- skills/$NAME)" ]] || fail "fetched dir is not gitignored"
manifest_json | jq -e --arg n "$NAME" '[.skill[]|select(.name==$n)]|length==1' >/dev/null || fail "duplicate manifest entries"

echo "== materialize (fresh-clone path)"
rm -rf "skills/$NAME"
make -s skills-materialize NAME=$NAME
[[ "$(jq -r .commit skills/$NAME/.source.json)" == "$commit" ]] || fail "materialize did not restore the pinned commit"

echo "== catalog + doctor"
make -s skills-catalog
make -s skills-doctor
make -s skills-catalog CHECK=1

echo "== delete (also drops the skill's scan baseline)"
mkdir -p skills/.security/skillspector && echo '{"version":2,"rules":[]}' > "skills/.security/skillspector/$NAME.json"
make -s skills-delete NAME=$NAME YES=1
[[ ! -e "skills/.security/skillspector/$NAME.json" ]] || fail "scan baseline survived delete"
make -s skills-catalog
manifest_json | jq -e --arg n "$NAME" '[.skill[]|select(.name==$n)]|length==0' >/dev/null || fail "manifest entry survived delete"
grep -qx "/skills/$NAME/" .gitignore && fail ".gitignore line survived delete"
[[ ! -e skills/$NAME ]] || fail "dir survived delete"
[[ -z "$(git status --porcelain)" ]] || { git status --porcelain; fail "tree not clean after round-trip"; }

echo "resource-manager smoke test: pass"
