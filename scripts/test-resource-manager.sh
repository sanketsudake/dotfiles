#!/usr/bin/env bash
# Smoke test for scripts/resource-manager.sh: fetch → materialize → doctor →
# delete round-trip for one small vendored skill. Runs in a throwaway clone
# of this repo so it never mutates the working tree. Needs network + jq.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone --quiet "$REPO_ROOT" "$tmp/repo"
cd "$tmp/repo"

REPO=mattpocock/skills SUBPATH=skills/productivity/grilling NAME=ci-smoke
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== fetch"
make -s skills-fetch REPO=$REPO SUBPATH=$SUBPATH NAME=$NAME CATEGORY=ci-smoke
commit=$(jq -re --arg n "$NAME" '.[]|select(.name==$n)|.commit' skills/vendored.json) || fail "no manifest entry"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || fail "manifest commit is not a sha: $commit"
grep -qx "/skills/$NAME/" .gitignore || fail ".gitignore line missing"
[[ -f skills/$NAME/SKILL.md ]] || fail "SKILL.md not fetched"
[[ "$(jq -r .commit skills/$NAME/.source.json)" == "$commit" ]] || fail "sidecar commit != manifest commit"
[[ -z "$(git status --porcelain -- skills/$NAME)" ]] || fail "fetched dir is not gitignored"
jq -e --arg n "$NAME" '[.[]|select(.name==$n)]|length==1' skills/vendored.json >/dev/null || fail "duplicate manifest entries"

echo "== materialize (fresh-clone path)"
rm -rf "skills/$NAME"
make -s skills-materialize NAME=$NAME
[[ "$(jq -r .commit skills/$NAME/.source.json)" == "$commit" ]] || fail "materialize did not restore the pinned commit"

echo "== catalog + doctor"
make -s skills-catalog
make -s skills-doctor
make -s skills-catalog CHECK=1

echo "== delete"
make -s skills-delete NAME=$NAME YES=1
make -s skills-catalog
jq -e --arg n "$NAME" '[.[]|select(.name==$n)]|length==0' skills/vendored.json >/dev/null || fail "manifest entry survived delete"
grep -qx "/skills/$NAME/" .gitignore && fail ".gitignore line survived delete"
[[ ! -e skills/$NAME ]] || fail "dir survived delete"
[[ -z "$(git status --porcelain)" ]] || { git status --porcelain; fail "tree not clean after round-trip"; }

echo "resource-manager smoke test: pass"
