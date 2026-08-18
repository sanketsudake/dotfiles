#!/usr/bin/env bash
#
# resource-manager.sh — fetch, list, update, and delete vendored resources
# (skills or agents) from arbitrary git repos, tracking each resource's source.
#
# A "skill" is a directory containing SKILL.md, vendored under skills/.
# An "agent" is a single .md file, vendored under claude/agents/.
#
# VENDORED SKILLS are recorded in a single committed manifest and their files
# are NOT committed — they are materialized from their pinned commit on install:
#   manifest: skills/vendored.json — an array of
#     {"name","repo","subpath","ref","commit","category","description"}
#   working files: skills/<name>/  — gitignored, rebuilt by `materialize`.
#   (materialize also writes a gitignored skills/<name>/.source.json marker.)
#
# AUTHORED skills (no upstream) and ALL AGENTS keep an in-tree sidecar and stay
# committed as before:
#   local sidecar: {"repo": null[, "category"]}
#   remote sidecar (agents): {"repo","subpath","ref","commit","fetched_at"[,"category"]}
#   skill sidecar: skills/<name>/.source.json        (inside the dir)
#   agent sidecar: claude/agents/<name>.source.json  (sibling of the .md)
# A resource with neither a manifest entry nor a sidecar is "unmanaged".
#
# Usage:
#   resource-manager.sh --kind {skill|agent} fetch  (--url URL | --repo REPO --subpath SUBPATH) [--ref REF] [--name NAME] [--category CAT] [--force]
#   resource-manager.sh --kind skill         materialize [--name NAME] [--force]
#   resource-manager.sh --kind {skill|agent} list
#   resource-manager.sh --kind {skill|agent} update (--name NAME | --all)
#   resource-manager.sh --kind {skill|agent} delete --name NAME [--yes]
#   resource-manager.sh --kind {skill|agent} category --name NAME --category CAT
#   resource-manager.sh --kind skill catalog [--check]
#   resource-manager.sh --kind skill suites [--check]
#   resource-manager.sh --kind skill budget [--check] [--limit TOKENS] [--top N]
#   resource-manager.sh --kind {skill|agent} doctor
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }
info() { printf '%s\n' "$*" >&2; }
rel()  { printf '%s' "${1#"$REPO_ROOT"/}"; }

command -v git >/dev/null || die "git is required"
command -v jq  >/dev/null || die "jq is required"

# Temp dirs are tracked globally and cleaned once on exit. A per-function
# RETURN trap would be wrong here: bash traps are global, so it would re-fire
# for callers after the local $tmp went out of scope.
TMPDIRS=()
cleanup_tmpdirs() { local d; for d in "${TMPDIRS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; return 0; }
trap cleanup_tmpdirs EXIT
# Create a tracked temp dir, returning its path in $MKTMP_DIR. The path is
# returned via a global rather than command substitution so the registry
# append runs in this shell, not a subshell (where it would be lost).
mktmp() { MKTMP_DIR="$(mktemp -d)"; TMPDIRS+=("$MKTMP_DIR"); }

# --- kind configuration ----------------------------------------------------
# KIND and RESOURCE_ROOT are set by the --kind selector before any command.

KIND=""
RESOURCE_ROOT=""
MANIFEST=""          # skills/vendored.json (skill kind only)
GITIGNORE="$REPO_ROOT/.gitignore"
SCAN_BASELINE_DIR="$REPO_ROOT/security/skillspector"   # per-skill SkillSpector baselines

configure_kind() {
  case "$KIND" in
    skill) RESOURCE_ROOT="$REPO_ROOT/skills"; MANIFEST="$RESOURCE_ROOT/vendored.json" ;;
    agent) RESOURCE_ROOT="$REPO_ROOT/claude/agents" ;;
    *) die "missing or unknown --kind '$KIND' (expected skill|agent)" ;;
  esac
}

# Primary artifact path for a resource (a dir for skills, a .md file for agents).
artifact_path() {
  case "$KIND" in
    skill) printf '%s/%s' "$RESOURCE_ROOT" "$1" ;;
    agent) printf '%s/%s.md' "$RESOURCE_ROOT" "$1" ;;
  esac
}

# Sidecar path: inside the dir for skills, sibling of the .md for agents.
sidecar_path() {
  case "$KIND" in
    skill) printf '%s/%s/.source.json' "$RESOURCE_ROOT" "$1" ;;
    agent) printf '%s/%s.source.json' "$RESOURCE_ROOT" "$1" ;;
  esac
}

# Default resource name from a subpath.
default_name() {
  case "$KIND" in
    skill) basename "$1" ;;
    agent) basename "$1" .md ;;
  esac
}

# Sparse-checkout path for a subpath: the dir itself for skills, the parent dir
# for agents (since the agent subpath is a file).
sparse_set_path() {
  case "$KIND" in
    skill) printf '%s' "$1" ;;
    agent) dirname "$1" ;;
  esac
}

# Validate that <clone>/<subpath> is a well-formed resource of this kind.
validate_artifact() {
  local src="$1" subpath="$2"
  case "$KIND" in
    skill) [[ -f "$src/SKILL.md" ]] || return 1 ;;
    agent) [[ "$subpath" == *.md && -f "$src" ]] || return 1 ;;
  esac
}

# Copy <clone>/<subpath> into the managed tree at <dest>.
copy_artifact() {
  local src="$1" dest="$2"
  mkdir -p "$RESOURCE_ROOT"
  case "$KIND" in
    skill) rm -rf "$dest"; cp -R "$src" "$dest" ;;
    agent) cp "$src" "$dest" ;;
  esac
}

# Emit "name<TAB>sidecar_path" for each managed resource of this kind.
iter_resources() {
  case "$KIND" in
    skill)
      local dir name
      for dir in "$RESOURCE_ROOT"/*/; do
        [[ -d "$dir" ]] || continue
        name="$(basename "$dir")"
        printf '%s\t%s\n' "$name" "$dir.source.json"
      done
      ;;
    agent)
      local f name
      for f in "$RESOURCE_ROOT"/*.md; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f" .md)"
        printf '%s\t%s\n' "$name" "$RESOURCE_ROOT/$name.source.json"
      done
      ;;
  esac
}

# --- shared helpers --------------------------------------------------------

# Normalize a repo reference into a clone URL.
#   owner/name            -> https://github.com/owner/name
#   https://..., git@...  -> passed through unchanged
normalize_repo() {
  local repo="$1"
  if [[ "$repo" == *"://"* || "$repo" == git@* ]]; then
    printf '%s' "$repo"
  elif [[ "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    printf 'https://github.com/%s' "$repo"
  else
    die "cannot interpret repo '$repo' (expected owner/name or a clone URL)"
  fi
}

# Parse a GitHub tree/blob URL into repo|ref|subpath, tab-separated.
#   https://github.com/owner/name/tree/<ref>/<subpath...>
parse_github_url() {
  local url="$1"
  local re='^https?://github\.com/([^/]+)/([^/]+)/(tree|blob)/([^/]+)/(.+)$'
  [[ "$url" =~ $re ]] || die "not a github tree/blob URL: $url"
  printf 'https://github.com/%s/%s\t%s\t%s' \
    "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}"
}

# Shallow sparse-clone <repo> at <ref> (empty ref = default branch) into <dest>,
# narrowed to <set_path> (empty or "." = top-level files only).
sparse_clone() {
  local repo="$1" ref="$2" set_path="$3" dest="$4"
  local args=(--depth=1 --filter=blob:none --sparse)
  [[ -n "$ref" ]] && args+=(--branch "$ref")
  git clone "${args[@]}" "$repo" "$dest" >/dev/null 2>&1 \
    || die "clone failed: $repo${ref:+ (ref $ref)}"
  if [[ -n "$set_path" && "$set_path" != "." ]]; then
    git -C "$dest" sparse-checkout set "$set_path" >/dev/null 2>&1 \
      || die "sparse-checkout failed for: $set_path"
  fi
}

# Write a remote sidecar for <name>. A non-empty <category> is recorded; empty
# is omitted (keeps uncategorized sidecars clean).
write_sidecar() {
  local name="$1" repo="$2" subpath="$3" ref="$4" commit="$5" category="${6:-}"
  local fetched_at; fetched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n \
    --arg repo "$repo" --arg subpath "$subpath" --arg ref "$ref" \
    --arg commit "$commit" --arg fetched_at "$fetched_at" --arg category "$category" \
    '{repo:$repo, subpath:$subpath, ref:$ref, commit:$commit, fetched_at:$fetched_at}
     + (if $category == "" then {} else {category:$category} end)' \
    > "$(sidecar_path "$name")"
}

# Shallow-fetch an EXACT commit (not a branch tip) from <repo> into <dest>,
# narrowed to <set_path>. GitHub serves arbitrary SHAs via fetch-by-sha.
fetch_commit() {
  local repo="$1" commit="$2" set_path="$3" dest="$4"
  git init -q "$dest" || return 1
  git -C "$dest" remote add origin "$repo" || return 1
  git -C "$dest" config extensions.partialClone origin
  git -C "$dest" fetch -q --depth=1 --filter=blob:none origin "$commit" 2>/dev/null || return 1
  if [[ -n "$set_path" && "$set_path" != "." ]]; then
    git -C "$dest" sparse-checkout set "$set_path" >/dev/null 2>&1 || return 1
  fi
  git -C "$dest" checkout -q FETCH_HEAD 2>/dev/null || return 1
}

# --- vendored-skill manifest (skills/vendored.json) ------------------------
# The manifest is the committed source of truth for vendored skills. Their
# files are gitignored and materialized from the pinned commit.

manifest_read()  { [[ -f "$MANIFEST" ]] && cat "$MANIFEST" || printf '[]'; }
manifest_names() { manifest_read | jq -r '.[].name'; }
manifest_entry() { manifest_read | jq -c --arg n "$1" 'map(select(.name==$n))[0] // empty'; }
manifest_field() { local e; e="$(manifest_entry "$1")"; [[ -n "$e" ]] && jq -r --arg f "$2" '.[$f] // ""' <<<"$e" || printf ''; }
is_vendored()    { [[ -n "$(manifest_entry "$1")" ]]; }

manifest_upsert() {  # name repo subpath ref commit category description
  local tmp; tmp="$(mktemp)"
  manifest_read | jq \
    --arg name "$1" --arg repo "$2" --arg subpath "$3" --arg ref "$4" \
    --arg commit "$5" --arg category "$6" --arg description "$7" \
    'map(select(.name != $name))
     + [{name:$name, repo:$repo, subpath:$subpath, ref:$ref, commit:$commit, category:$category, description:$description}]
     | sort_by(.name)' \
    > "$tmp" && mv "$tmp" "$MANIFEST"
}
manifest_remove() {
  local tmp; tmp="$(mktemp)"
  manifest_read | jq --arg n "$1" 'map(select(.name != $n))' > "$tmp" && mv "$tmp" "$MANIFEST"
}
manifest_set_category() {
  local tmp; tmp="$(mktemp)"
  manifest_read | jq --arg n "$1" --arg c "$2" 'map(if .name==$n then .category=$c else . end)' > "$tmp" && mv "$tmp" "$MANIFEST"
}

# --- skill accessors (dual-source: manifest for vendored, sidecar/SKILL.md
# for authored) so catalog / suites / doctor work on a bare (un-materialized)
# checkout as well as a materialized one.

all_skill_names() {
  { manifest_names
    local d; for d in "$RESOURCE_ROOT"/*/; do [[ -d "$d" ]] && basename "$d"; done
  } | sort -u
}
skill_exists()      { is_vendored "$1" || [[ -f "$RESOURCE_ROOT/$1/SKILL.md" ]]; }
skill_description() {
  if is_vendored "$1"; then manifest_field "$1" description
  else frontmatter_field "$RESOURCE_ROOT/$1/SKILL.md" description; fi
}
skill_category() {
  local c sc
  if is_vendored "$1"; then c="$(manifest_field "$1" category)"; printf '%s' "${c:-uncategorized}"
  else
    sc="$RESOURCE_ROOT/$1/.source.json"
    if [[ -f "$sc" ]]; then jq -r '.category // "uncategorized"' "$sc"; else printf 'uncategorized'; fi
  fi
}
# Catalog link target for a skill. Vendored skill dirs are gitignored (absent on
# GitHub), so link to their upstream source at the pinned commit; authored dirs
# are committed, so link to the in-repo SKILL.md.
skill_catalog_link() {
  local repo subpath commit
  if is_vendored "$1"; then
    repo="$(manifest_field "$1" repo)"; subpath="$(manifest_field "$1" subpath)"
    commit="$(manifest_field "$1" commit)"
    if [[ -n "$repo" && "$repo" != "null" ]]; then
      printf '%s/tree/%s/%s' "${repo%/}" "${commit:-HEAD}" "$subpath"
      return
    fi
  fi
  printf '%s/SKILL.md' "$1"
}

# --- .gitignore managed block (the vendored skill dirs) --------------------
GI_BEGIN='# >>> vendored skills (managed by resource-manager.sh; materialized by `make install`)'
GI_END='# <<< vendored skills'

# Rewrite the managed block so it lists exactly the current manifest's skill
# dirs. Idempotent; creates the block on first use.
sync_gitignore() {
  local blk tmp
  blk="$(mktemp)"; tmp="$(mktemp)"
  { printf '%s\n' "$GI_BEGIN"
    manifest_names | sort | while IFS= read -r n; do [[ -n "$n" ]] && printf '/skills/%s/\n' "$n"; done
    printf '%s\n' "$GI_END"
  } > "$blk"
  if [[ -f "$GITIGNORE" ]] && grep -qxF "$GI_BEGIN" "$GITIGNORE"; then
    awk -v b="$GI_BEGIN" -v e="$GI_END" -v bf="$blk" '
      $0==b { while ((getline l < bf) > 0) print l; close(bf); skip=1; next }
      $0==e { skip=0; next }
      !skip { print }
    ' "$GITIGNORE" > "$tmp"
  else
    { [[ -f "$GITIGNORE" ]] && cat "$GITIGNORE"; printf '\n'; cat "$blk"; } > "$tmp"
  fi
  mv "$tmp" "$GITIGNORE"; rm -f "$blk"
}

# --- materialize -----------------------------------------------------------
# Reconstruct one vendored skill's working files from its pinned commit.
# Idempotent: skips if already present at the right commit (unless force).
materialize_one() {
  local name="$1" force="${2:-0}"
  local entry; entry="$(manifest_entry "$name")"
  [[ -n "$entry" ]] || { err "$name: not in manifest"; return 1; }
  local repo subpath ref commit category dest
  repo="$(jq -r '.repo' <<<"$entry")"
  subpath="$(jq -r '.subpath' <<<"$entry")"
  ref="$(jq -r '.ref' <<<"$entry")"
  commit="$(jq -r '.commit' <<<"$entry")"
  category="$(jq -r '.category' <<<"$entry")"
  dest="$(artifact_path "$name")"
  if [[ "$force" -ne 1 && -f "$dest/SKILL.md" && -f "$dest/.source.json" \
        && "$(jq -r '.commit // ""' "$dest/.source.json")" == "$commit" ]]; then
    return 0   # already materialized at the right commit
  fi
  local tmp; mktmp; tmp="$MKTMP_DIR"
  fetch_commit "$repo" "$commit" "$(sparse_set_path "$subpath")" "$tmp/repo" \
    || { err "$name: could not fetch ${commit:0:7} from $repo (offline?)"; return 1; }
  validate_artifact "$tmp/repo/$subpath" "$subpath" \
    || { err "$name: $subpath is not a valid skill at ${commit:0:7}"; return 1; }
  copy_artifact "$tmp/repo/$subpath" "$dest"
  write_sidecar "$name" "$repo" "$subpath" "$ref" "$commit" "$category"
  info "materialized $(rel "$dest") @ ${commit:0:7}"
}

# Materialize all vendored skills (or one via --name). Missing/offline fetches
# are warnings, not failures: `make install` must not break offline.
# Names of stale vendored skill dirs: on disk with a remote sidecar
# (.source.json repo != null) but no manifest entry, and NOT git-tracked. The
# tracked-guard guarantees a committed authored skill is never pruned, even if
# its sidecar is somehow misconfigured. Skill kind only.
find_vendored_orphans() {
  [[ "$KIND" == "skill" ]] || return 0
  local d name repo
  for d in "$RESOURCE_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    [[ -f "$d/.source.json" ]] || continue
    repo="$(jq -r '.repo // "null"' "$d/.source.json" 2>/dev/null || echo null)"
    [[ "$repo" != "null" && -n "$repo" ]] || continue   # authored/unmanaged -> skip
    is_vendored "$name" && continue                       # still in manifest -> not orphan
    git -C "$REPO_ROOT" ls-files --error-unmatch "skills/$name" >/dev/null 2>&1 && continue  # tracked -> never prune
    printf '%s\n' "$name"
  done
}

cmd_materialize() {
  [[ "$KIND" == "skill" ]] || die "materialize: only supported for --kind skill"
  local name="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)  name="$2"; shift 2 ;;
      --force) force=1; shift ;;
      *) die "materialize: unknown argument '$1'" ;;
    esac
  done
  [[ -f "$MANIFEST" ]] || { info "materialize: no $(rel "$MANIFEST"), nothing to do"; return 0; }
  if [[ -n "$name" ]]; then
    is_vendored "$name" || die "$name: not a vendored skill (not in manifest)"
    materialize_one "$name" "$force" || return 1
    return 0
  fi
  local n ok=0 fail=0
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    if materialize_one "$n" "$force"; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
  done < <(manifest_names)

  # Reconcile: a vendored dir dropped from the manifest is stale — remove it so the
  # on-disk vendored set matches the manifest, rather than leaving a skill active in
  # the profiles that we intended to delete. Guarded (untracked, remote-sidecar only).
  local orphan pruned=0
  while IFS= read -r orphan; do
    [[ -n "$orphan" ]] || continue
    rm -rf "${RESOURCE_ROOT:?}/$orphan"
    info "pruned stale vendored skill $orphan (no longer in manifest)"
    pruned=$((pruned + 1))
  done < <(find_vendored_orphans)

  local summary="materialize: $ok skill(s) present"
  [[ "$pruned" -gt 0 ]] && summary="$summary, $pruned pruned"
  if [[ "$fail" -gt 0 ]]; then
    info "$summary, $fail could not be fetched (offline? those skills are unavailable until re-run online)"
  else
    info "$summary"
  fi
  return 0
}

# --- subcommands -----------------------------------------------------------

# --- security scan gate (skills) ---------------------------------------------
# Run scripts/skills-scan.py (NVIDIA SkillSpector) on a staged skill dir before
# it is installed by fetch/update. A failed scan aborts the install; set
# SKILLS_SCAN=0 to skip explicitly (the skip is logged). When skillspector is
# not installed the gate warns and lets the install through — install it with
# `make skillspector-install` (pinned to SKILLSPECTOR_REF in the Makefile).
scan_gate() {  # staged_dir name
  [[ "$KIND" == "skill" ]] || return 0
  if [[ "${SKILLS_SCAN:-1}" == "0" ]]; then
    info "$2: security scan skipped (SKILLS_SCAN=0)"; return 0
  fi
  info "$2: security scan (skillspector, static)"
  # skills-scan.py exports its own copy of the dir; exit 3 = scanner not installed.
  python3 "$REPO_ROOT/scripts/skills-scan.py" --path "$1" --name "$2" --quiet >&2
  case $? in
    0) return 0 ;;
    3) info "$2: WARNING — skillspector not installed, skill NOT security-scanned"; return 0 ;;
    *) err "$2: security scan FAILED — not installed. Review the findings above; accept a false positive with a reason in security/skillspector/$2.json, or re-run with SKILLS_SCAN=0 to install unscanned."; return 1 ;;
  esac
}

cmd_fetch() {
  local url="" repo="" subpath="" ref="" name="" category="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url)      url="$2"; shift 2 ;;
      --repo)     repo="$2"; shift 2 ;;
      --subpath)  subpath="$2"; shift 2 ;;
      --ref)      ref="$2"; shift 2 ;;
      --name)     name="$2"; shift 2 ;;
      --category) category="$2"; shift 2 ;;
      --force)    force=1; shift ;;
      *) die "fetch: unknown argument '$1'" ;;
    esac
  done

  # A URL supplies defaults; explicit flags override.
  if [[ -n "$url" ]]; then
    local parsed; parsed="$(parse_github_url "$url")"
    IFS=$'\t' read -r u_repo u_ref u_subpath <<<"$parsed"
    [[ -z "$repo"    ]] && repo="$u_repo"
    [[ -z "$ref"     ]] && ref="$u_ref"
    [[ -z "$subpath" ]] && subpath="$u_subpath"
  fi

  [[ -n "$repo"    ]] || die "fetch: --repo or --url is required"
  [[ -n "$subpath" ]] || die "fetch: --subpath or --url is required"
  subpath="${subpath%/}"
  [[ -n "$name" ]] || name="$(default_name "$subpath")"

  local dest; dest="$(artifact_path "$name")"
  if [[ "$KIND" == "skill" ]]; then
    if is_vendored "$name" && [[ "$force" -ne 1 ]]; then
      die "$name is already in the manifest (use FORCE=1 to overwrite, or skills-update to refresh)"
    fi
  elif [[ -e "$dest" && "$force" -ne 1 ]]; then
    die "$(rel "$dest") already exists (use FORCE=1 to overwrite, or ${KIND}s-update to refresh)"
  fi

  repo="$(normalize_repo "$repo")"
  local tmp; mktmp; tmp="$MKTMP_DIR"

  info "fetching $KIND $name from $repo${ref:+ @ $ref} ($subpath)"
  sparse_clone "$repo" "$ref" "$(sparse_set_path "$subpath")" "$tmp/repo"

  local commit; commit="$(git -C "$tmp/repo" rev-parse HEAD)"
  [[ -n "$ref" ]] || ref="$(git -C "$tmp/repo" rev-parse --abbrev-ref HEAD)"
  validate_artifact "$tmp/repo/$subpath" "$subpath" \
    || die "$subpath in $repo is not a valid $KIND"
  scan_gate "$tmp/repo/$subpath" "$name" || die "$name: refused by the security scan gate"

  copy_artifact "$tmp/repo/$subpath" "$dest"
  if [[ "$KIND" == "skill" ]]; then
    local description; description="$(frontmatter_field "$dest/SKILL.md" description)"
    manifest_upsert "$name" "$repo" "$subpath" "$ref" "$commit" "$category" "$description"
    write_sidecar "$name" "$repo" "$subpath" "$ref" "$commit" "$category"  # gitignored materialize marker
    sync_gitignore
  else
    write_sidecar "$name" "$repo" "$subpath" "$ref" "$commit" "$category"
  fi
  info "fetched $(rel "$dest") @ ${commit:0:7}${category:+ [$category]}"
}

# Build list rows from in-tree sidecars (agents, and authored/unmanaged skill
# dirs). Emits: category\tname\tstatus\trepo\tsubpath\tref\tcommit\tfetched.
list_data_generic() {
  local name sidecar repo subpath ref commit fetched category status
  while IFS=$'\t' read -r name sidecar; do
    [[ -n "$name" ]] || continue
    repo=-; subpath=-; ref=-; commit=-; fetched=-
    if [[ ! -f "$sidecar" ]]; then
      status=unmanaged; category=uncategorized
    else
      category="$(jq -r '.category // "uncategorized"' "$sidecar")"
      repo="$(jq -r '.repo // empty' "$sidecar")"
      if [[ -z "$repo" ]]; then
        status=local; repo=-
      else
        status=remote
        subpath="$(jq -r '.subpath // "-"' "$sidecar")"
        ref="$(jq -r '.ref // "-"' "$sidecar")"
        commit="$(jq -r '.commit // "-"' "$sidecar")"; commit="${commit:0:7}"
        fetched="$(jq -r '.fetched_at // "-"' "$sidecar")"
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$category" "$name" "$status" "$repo" "$subpath" "$ref" "$commit" "$fetched"
  done < <(iter_resources)
}

# Build skill list rows: vendored from the manifest (status materialized/pinned
# by whether the working tree is present), authored/unmanaged from their dirs.
list_data_skill() {
  local name entry repo subpath ref commit category status dir sidecar
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    entry="$(manifest_entry "$name")"
    repo="$(jq -r '.repo' <<<"$entry")"
    subpath="$(jq -r '.subpath' <<<"$entry")"
    ref="$(jq -r '.ref' <<<"$entry")"
    commit="$(jq -r '.commit' <<<"$entry")"; commit="${commit:0:7}"
    category="$(jq -r '.category // "uncategorized"' <<<"$entry")"; [[ -n "$category" ]] || category=uncategorized
    if [[ -f "$RESOURCE_ROOT/$name/SKILL.md" ]]; then status=materialized; else status=pinned; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$category" "$name" "$status" "$repo" "$subpath" "$ref" "$commit" "-"
  done < <(manifest_names)
  for dir in "$RESOURCE_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    is_vendored "$name" && continue
    sidecar="$dir.source.json"
    if [[ ! -f "$sidecar" ]]; then
      status=unmanaged; category=uncategorized
    else
      category="$(jq -r '.category // "uncategorized"' "$sidecar")"
      status=local
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$category" "$name" "$status" "-" "-" "-" "-" "-"
  done
}

# List resources grouped by category, rows bucketed under a `<category>
# (<count>)` header with an aligned table.
cmd_list() {
  local data cat count
  if [[ "$KIND" == "skill" ]]; then
    data="$(list_data_skill | sort -t$'\t' -k1,1 -k2,2)"
  else
    data="$(list_data_generic)"
  fi

  [[ -n "$data" ]] || { info "no ${KIND}s found"; return 0; }

  while IFS= read -r cat; do
    [[ -n "$cat" ]] || continue
    count="$(printf '%s' "$data" | awk -F'\t' -v c="$cat" '$1==c' | grep -c .)"
    printf '\n%s (%s)\n' "$cat" "$count"
    { printf 'NAME\tSTATUS\tREPO\tSUBPATH\tREF\tCOMMIT\tFETCHED_AT\n'
      printf '%s' "$data" | awk -F'\t' -v c="$cat" '$1==c {print $2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8}'
    } | column -t -s $'\t'
  done < <(printf '%s' "$data" | cut -f1 | sort -u)
}

# Re-fetch one remote resource in place. Reports via stderr.
# Re-resolve a vendored skill's ref to the newest upstream commit; if it moved,
# re-materialize, refresh the pinned commit + cached description in the manifest.
update_one_skill() {
  local name="$1"
  if ! is_vendored "$name"; then
    if [[ -d "$RESOURCE_ROOT/$name" ]]; then
      info "$name: authored skill, nothing to update"; return 0
    fi
    err "$name: no such skill"; return 1
  fi
  local entry repo subpath ref old_commit category
  entry="$(manifest_entry "$name")"
  repo="$(jq -r '.repo' <<<"$entry")"
  subpath="$(jq -r '.subpath' <<<"$entry")"
  ref="$(jq -r '.ref' <<<"$entry")"
  old_commit="$(jq -r '.commit' <<<"$entry")"
  category="$(jq -r '.category' <<<"$entry")"

  local tmp; mktmp; tmp="$MKTMP_DIR"
  sparse_clone "$repo" "$ref" "$(sparse_set_path "$subpath")" "$tmp/repo"
  local new_commit; new_commit="$(git -C "$tmp/repo" rev-parse HEAD)"
  if [[ "$new_commit" == "$old_commit" ]]; then
    info "$name: up to date (${old_commit:0:7})"; return 0
  fi
  validate_artifact "$tmp/repo/$subpath" "$subpath" \
    || { err "$name: $subpath is no longer a valid skill upstream, skipping"; return 1; }
  scan_gate "$tmp/repo/$subpath" "$name" \
    || { err "$name: upstream ${new_commit:0:7} refused by the security scan gate, keeping ${old_commit:0:7}"; return 1; }

  local dest description
  dest="$(artifact_path "$name")"
  copy_artifact "$tmp/repo/$subpath" "$dest"
  description="$(frontmatter_field "$dest/SKILL.md" description)"
  manifest_upsert "$name" "$repo" "$subpath" "$ref" "$new_commit" "$category" "$description"
  write_sidecar "$name" "$repo" "$subpath" "$ref" "$new_commit" "$category"
  info "$name: updated ${old_commit:0:7} -> ${new_commit:0:7}"
}

update_one() {
  local name="$1"
  [[ "$KIND" == "skill" ]] && { update_one_skill "$name"; return; }
  local artifact sidecar
  artifact="$(artifact_path "$name")"
  sidecar="$(sidecar_path "$name")"
  [[ -e "$artifact" ]] || { err "$name: no such $KIND"; return 1; }
  if [[ ! -f "$sidecar" ]]; then
    info "$name: unmanaged (no .source.json), skipping"
    return 0
  fi
  local repo; repo="$(jq -r '.repo // empty' "$sidecar")"
  if [[ -z "$repo" ]]; then
    info "$name: local $KIND, nothing to update"
    return 0
  fi
  local subpath ref old_commit category
  subpath="$(jq -r '.subpath' "$sidecar")"
  ref="$(jq -r '.ref' "$sidecar")"
  old_commit="$(jq -r '.commit' "$sidecar")"
  category="$(jq -r '.category // ""' "$sidecar")"   # preserve across re-fetch

  local tmp; mktmp; tmp="$MKTMP_DIR"
  sparse_clone "$repo" "$ref" "$(sparse_set_path "$subpath")" "$tmp/repo"
  local new_commit; new_commit="$(git -C "$tmp/repo" rev-parse HEAD)"

  if [[ "$new_commit" == "$old_commit" ]]; then
    info "$name: up to date (${old_commit:0:7})"
    return 0
  fi
  validate_artifact "$tmp/repo/$subpath" "$subpath" \
    || { err "$name: subpath $subpath is no longer a valid $KIND upstream, skipping"; return 1; }

  copy_artifact "$tmp/repo/$subpath" "$artifact"
  write_sidecar "$name" "$repo" "$subpath" "$ref" "$new_commit" "$category"
  info "$name: updated ${old_commit:0:7} -> ${new_commit:0:7}"
}

cmd_update() {
  local name="" all=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --all)  all=1; shift ;;
      *) die "update: unknown argument '$1'" ;;
    esac
  done

  if [[ "$all" -eq 1 ]]; then
    if [[ "$KIND" == "skill" ]]; then
      local n
      while IFS= read -r n; do
        [[ -n "$n" ]] && { update_one_skill "$n" || true; }
      done < <(manifest_names)
    else
      local n s
      while IFS=$'\t' read -r n s; do
        [[ -f "$s" ]] || continue
        [[ "$(jq -r '.repo // empty' "$s")" ]] || continue
        update_one "$n" || true
      done < <(iter_resources)
    fi
    return 0
  fi

  [[ -n "$name" ]] || die "update: --name NAME or --all is required"
  update_one "$name"
}

cmd_delete() {
  local name="" yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --yes)  yes=1; shift ;;
      *) die "delete: unknown argument '$1'" ;;
    esac
  done
  [[ -n "$name" ]] || die "delete: --name NAME is required"
  local artifact; artifact="$(artifact_path "$name")"
  local vendored=0
  [[ "$KIND" == "skill" ]] && is_vendored "$name" && vendored=1
  # A vendored skill exists in the manifest even if its files aren't materialized.
  if [[ "$vendored" -ne 1 && ! -e "$artifact" ]]; then
    die "$(rel "$artifact") does not exist"
  fi

  if [[ "$yes" -ne 1 ]]; then
    local reply
    printf 'Delete %s %s? [y/N] ' "$KIND" "$name" >&2
    read -r reply </dev/tty || reply=""
    [[ "$reply" == "y" || "$reply" == "Y" ]] || { info "aborted"; return 0; }
  fi
  if [[ "$vendored" -eq 1 ]]; then
    manifest_remove "$name"
    rm -rf "$artifact"
    sync_gitignore
    drop_scan_baseline "$name"
    info "deleted vendored skill $name (removed from manifest, working tree, and .gitignore)"
    return 0
  fi
  case "$KIND" in
    skill) rm -rf "$artifact"; drop_scan_baseline "$name" ;;
    agent) rm -f "$artifact" "$(sidecar_path "$name")" ;;
  esac
  info "deleted $(rel "$artifact")"
}

# A skill's accepted-findings file for the security scan (see scan_gate).
drop_scan_baseline() {  # name
  local f="$SCAN_BASELINE_DIR/$1.json"
  [[ -f "$f" ]] || return 0
  rm -f "$f"
  info "removed $(rel "$f") (scan baseline of a deleted skill)"
}

# Read a scalar frontmatter field from a markdown file, joining folded (`>`)
# and indented continuation lines into one space-separated value.
frontmatter_field() {
  local file="$1" field="$2"
  awk -v f="$field" '
    NR == 1 { if ($0 == "---") { infm = 1; next } else { exit } }
    infm && $0 == "---" { exit }
    !infm { next }
    capturing {
      if ($0 ~ /^[[:space:]]+[^[:space:]]/) { sub(/^[[:space:]]+/, ""); val = val (val == "" ? "" : " ") $0; next }
      exit
    }
    $0 ~ "^" f ":" {
      v = $0; sub("^" f ":[[:space:]]*", "", v)
      if (v !~ /^[>|][+-]?$/) val = v
      capturing = 1
    }
    END { print val }
  ' "$file"
}

# One-line "purpose" for a catalog row: the description collapsed to a single
# sentence, pipes escaped for markdown tables, truncated if still long.
purpose_from_description() {
  local desc="$1" purpose
  purpose="$(printf '%s' "$desc" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
  purpose="${purpose#\"}"; purpose="${purpose%\"}"
  # Shield common abbreviations so the first-sentence split below doesn't
  # break on them, then restore the spaces afterwards.
  local sep=$'\x01' abbr
  for abbr in e.g. i.e. etc. vs.; do
    purpose="${purpose//"$abbr" /$abbr$sep}"
  done
  case "$purpose" in
    *". "*) purpose="${purpose%%. *}." ;;
  esac
  purpose="${purpose//$sep/ }"
  purpose="${purpose//|/\\|}"
  if (( ${#purpose} > 160 )); then
    purpose="${purpose:0:157}..."
  fi
  printf '%s' "$purpose"
}

# Render the markdown skills catalog (a standalone skills/README.md with
# category-grouped tables) to stdout.
render_catalog() {
  [[ "$KIND" == "skill" ]] || die "catalog: only supported for --kind skill"
  local data="" name category desc purpose link total
  # all_skill_names is sorted, so rows are alphabetical within each category.
  # Vendored skills draw category/description from the manifest (so the catalog
  # renders on a bare checkout); authored skills from their sidecar + SKILL.md.
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    skill_exists "$name" || continue
    category="$(skill_category "$name")"
    desc="$(skill_description "$name")"
    purpose="$(purpose_from_description "$desc")"
    [[ -n "$purpose" ]] || purpose="(no description)"
    link="$(skill_catalog_link "$name")"
    data+="$category"$'\t'"$name"$'\t'"$purpose"$'\t'"$link"$'\n'
  done < <(all_skill_names)
  [[ -n "$data" ]] || { info "no skills found"; return 0; }

  total="$(printf '%s' "$data" | grep -c .)"

  # Categories alphabetically, uncategorized last.
  local cats cat first=1 n
  cats="$(printf '%s' "$data" | cut -f1 | sort -u | grep -vx uncategorized || true)"
  if printf '%s' "$data" | cut -f1 | grep -qx uncategorized; then
    cats="$cats"$'\n'uncategorized
  fi

  printf '# Skills catalog\n\n'
  printf '%s skills, grouped by `category` (from `skills/vendored.json` for vendored skills, from each `.source.json` sidecar for authored ones).\n' "$total"
  printf 'Each name links to its source: authored skills to the in-repo `SKILL.md`, vendored skills to their upstream repo at the pinned commit (their dirs are gitignored, so they are not present in this repo).\n'
  printf 'Generated by `make skills-catalog` — do not edit by hand (`make skills-doctor` flags a stale file).\n\n'

  # Category index — each links to that category's `## <category>` heading. The
  # count is kept out of the heading so the GitHub anchor (`#<category>`) stays
  # stable as skills are added or removed, and per-category links stay shareable.
  printf '**Categories:** '
  while IFS= read -r cat; do
    [[ -n "$cat" ]] || continue
    [[ "$first" -eq 1 ]] || printf ' · '
    first=0
    printf '[%s](#%s)' "$cat" "$cat"
  done <<<"$cats"
  printf '\n'

  while IFS= read -r cat; do
    [[ -n "$cat" ]] || continue
    n="$(printf '%s' "$data" | awk -F'\t' -v c="$cat" '$1==c' | grep -c .)"
    printf '\n## %s\n\n' "$cat"
    printf '%s skill%s.\n\n' "$n" "$([[ "$n" -eq 1 ]] && printf '' || printf 's')"
    printf '| Skill | Purpose |\n|-------|---------|\n'
    printf '%s' "$data" | awk -F'\t' -v c="$cat" \
      '$1==c {printf "| [`%s`](%s) | %s |\n", $2, $4, $3}'
  done <<<"$cats"
}

# Regenerate the standalone catalog at skills/README.md.
# With --check, don't write: exit 1 if the file is stale.
cmd_catalog() {
  local check=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) check=1; shift ;;
      *) die "catalog: unknown argument '$1'" ;;
    esac
  done
  local catalog="$RESOURCE_ROOT/README.md"
  local tmp; mktmp; tmp="$MKTMP_DIR"
  render_catalog > "$tmp/README.md"

  if [[ "$check" -eq 1 ]]; then
    [[ -f "$catalog" ]] && diff -q "$catalog" "$tmp/README.md" >/dev/null \
      || { err "$(rel "$catalog") is stale (run: make skills-catalog)"; return 1; }
    info "catalog: up to date"
    return 0
  fi
  if [[ -f "$catalog" ]] && diff -q "$catalog" "$tmp/README.md" >/dev/null; then
    info "catalog: up to date"
  else
    cp "$tmp/README.md" "$catalog"
    info "catalog: $(rel "$catalog") regenerated"
  fi
}

# --- suites ------------------------------------------------------------------
# A "suite" is a curated, ordered set of skills with a landing page:
#   suites/<name>/suite.json  {"title", "tagline"?, "skills": [ordered names]}
#   suites/<name>/README.md   hand-written, with one machine-owned region
# `suites` regenerates each README's marked region (skill table + install
# command) and the Suites index in the top-level README.md.

SUITES_ROOT="$REPO_ROOT/suites"
SUITE_INSTALL_REPO="sanketsudake/harness-configs"
SUITE_BEGIN='<!-- suite-skills:begin -->'
SUITE_END='<!-- suite-skills:end -->'
SUITES_INDEX_BEGIN='<!-- suites:begin -->'
SUITES_INDEX_END='<!-- suites:end -->'

# Validate a suite.json: title present, skills a non-empty array, every
# member a real skill. Reports via err and returns 1 (no die: doctor must
# be able to accumulate suite problems and still print its summary).
validate_suite_manifest() {
  local manifest="$1" skill bad=0
  jq -e 'has("title") and (.skills | type == "array" and length > 0)' \
    "$manifest" >/dev/null 2>&1 \
    || { err "$(rel "$manifest"): must have a title and a non-empty skills array"; return 1; }
  while IFS= read -r skill; do
    skill_exists "$skill" \
      || { err "$(rel "$manifest"): skill '$skill' not found (no manifest entry or skills/$skill/SKILL.md)"; bad=1; }
  done < <(jq -r '.skills[]' "$manifest")
  return "$bad"
}

# Render one suite's generated region (skill table + install command) to
# stdout, in manifest order.
render_suite_block() {
  local manifest="$1" skill desc purpose link
  printf '## Skills in this suite\n\n'
  printf '| Skill | Purpose |\n|-------|---------|\n'
  while IFS= read -r skill; do
    desc="$(skill_description "$skill")"
    purpose="$(purpose_from_description "$desc")"
    [[ -n "$purpose" ]] || purpose="(no description)"
    # Vendored skills → upstream URL (their dirs are gitignored); authored →
    # the in-repo SKILL.md, relative to this suite's dir.
    link="$(skill_catalog_link "$skill")"
    [[ "$link" == http* ]] || link="../../skills/$skill/SKILL.md"
    printf '| [`%s`](%s) | %s |\n' "$skill" "$link" "$purpose"
  done < <(jq -r '.skills[]' "$manifest")
  printf '\n## Install\n\n'
  printf 'With the [skills.sh](https://www.skills.sh/) CLI (needs Node.js):\n\n'
  printf '```bash\nnpx skills add %s \\\n' "$SUITE_INSTALL_REPO"
  while IFS= read -r skill; do
    printf '  --skill %s \\\n' "$skill"
  done < <(jq -r '.skills[]' "$manifest")
  printf -- '  -y\n```\n'
}

# Render the Suites index (for the top-level README) to stdout.
render_suites_index() {
  local manifest dir title tagline
  printf '**Suites** — curated skill sets with their own landing pages:\n\n'
  for manifest in "$SUITES_ROOT"/*/suite.json; do
    [[ -f "$manifest" ]] || continue
    dir="$(basename "$(dirname "$manifest")")"
    title="$(jq -r '.title' "$manifest")"
    tagline="$(jq -r '.tagline // ""' "$manifest")"
    printf -- '- **[%s](suites/%s/)**%s\n' "$title" "$dir" "${tagline:+ — $tagline}"
  done
}

# Splice <block_file> between the <begin>/<end> marker lines of <file>,
# printing the result to stdout. Markers themselves are kept.
splice_marked_region() {
  local file="$1" begin="$2" end="$3" block_file="$4"
  awk -v b="$begin" -v e="$end" -v bf="$block_file" '
    $0 == b { print; while ((getline l < bf) > 0) print l; close(bf); skip = 1; next }
    $0 == e { skip = 0 }
    !skip { print }
  ' "$file"
}

# Regenerate one file's marked region from <block_file>.
# check=1: don't write; return 1 if stale, missing, or duplicated markers
# (err, not die — callers accumulate).
regen_marked_region() {
  local file="$1" begin="$2" end="$3" block_file="$4" check="$5"
  if [[ "$(grep -cxF "$begin" "$file")" -ne 1 || "$(grep -cxF "$end" "$file")" -ne 1 ]]; then
    err "$(rel "$file"): needs exactly one '$begin' and one '$end' marker line"
    return 1
  fi
  local tmp; mktmp; tmp="$MKTMP_DIR"
  splice_marked_region "$file" "$begin" "$end" "$block_file" > "$tmp/out"
  if diff -q "$file" "$tmp/out" >/dev/null; then
    return 0
  fi
  if [[ "$check" -eq 1 ]]; then
    err "$(rel "$file") is stale (run: make suites-catalog)"
    return 1
  fi
  cp "$tmp/out" "$file"
  info "suites: $(rel "$file") regenerated"
}

# Regenerate every suite README's marked region and the top-level README's
# Suites index. With --check, verify only (exit 1 if anything is stale).
cmd_suites() {
  [[ "$KIND" == "skill" ]] || die "suites: only supported for --kind skill"
  local check=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) check=1; shift ;;
      *) die "suites: unknown argument '$1'" ;;
    esac
  done

  local manifests=("$SUITES_ROOT"/*/suite.json)
  [[ -f "${manifests[0]:-}" ]] || { info "suites: none found"; return 0; }

  local manifest readme stale=0 tmp
  for manifest in "${manifests[@]}"; do
    validate_suite_manifest "$manifest" || { stale=$((stale + 1)); continue; }
    readme="$(dirname "$manifest")/README.md"
    [[ -f "$readme" ]] || { err "$(rel "$readme") does not exist"; stale=$((stale + 1)); continue; }
    mktmp; tmp="$MKTMP_DIR"
    render_suite_block "$manifest" > "$tmp/block"
    regen_marked_region "$readme" "$SUITE_BEGIN" "$SUITE_END" "$tmp/block" "$check" \
      || stale=$((stale + 1))
  done

  # Suites index in the top-level README. Optional until the markers exist
  # (they are added by a separate change); absence is a note, not an error.
  local root_readme="$REPO_ROOT/README.md"
  if grep -qxF "$SUITES_INDEX_BEGIN" "$root_readme"; then
    mktmp; tmp="$MKTMP_DIR"
    render_suites_index > "$tmp/index"
    regen_marked_region "$root_readme" "$SUITES_INDEX_BEGIN" "$SUITES_INDEX_END" "$tmp/index" "$check" \
      || stale=$((stale + 1))
  else
    info "suites: README.md has no suites index markers, skipping index"
  fi

  if [[ "$stale" -gt 0 ]]; then
    err "suites: $stale problem(s) found"
    return 1
  fi
  [[ "$check" -eq 1 ]] && info "suites: up to date"
  return 0
}

# Validate every resource of this kind; exit 1 if any problem is found.
# Skills additionally verify the README catalog + suites blocks are current.
# Everything is checked from committed state — no materialization required.
# --- budget ------------------------------------------------------------------
# Estimate the always-loaded context this repo injects into every Claude Code
# session — the shared CLAUDE.md + rules, every skill's name+description, every
# agent's name+description, and every command's description. Tokens ≈ chars/4
# (no API, no key). --check exits 1 when the total exceeds --limit (env
# CONTEXT_BUDGET_TOKENS, default 12000). Plugin/marketplace skills are outside
# this repo and not counted.
est_tokens() { local c; c="$(printf '%s' "$1" | wc -c | tr -d ' ')"; echo $(( (c + 3) / 4 )); }

cmd_budget() {
  [[ "$KIND" == "skill" ]] || die "budget: only supported for --kind skill"
  local check=0 limit="${CONTEXT_BUDGET_TOKENS:-12000}" top=10
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) check=1; shift ;;
      --limit) limit="$2"; shift 2 ;;
      --top)   top="$2"; shift 2 ;;
      *) die "budget: unknown argument '$1'" ;;
    esac
  done
  [[ "$limit" =~ ^[1-9][0-9]*$ ]] || die "budget: limit must be a positive integer (got '$limit'; set CONTEXT_BUDGET_TOKENS or --limit)"
  local claude_dir="$REPO_ROOT/claude"
  # Each segment is "N items, T estimated tokens"; sum_segment reads whole
  # files, sum_descs reads "name: description" strings from stdin, one per line.
  sum_segment() { local t=0 n=0 f; for f in "$@"; do [[ -f "$f" ]] || continue; t=$((t + $(est_tokens "$(cat "$f")"))); n=$((n + 1)); done; echo "$t $n"; }
  sum_descs()   { local t=0 n=0 line; while IFS= read -r line; do [[ -n "$line" ]] || continue; t=$((t + $(est_tokens "$line"))); n=$((n + 1)); done; echo "$t $n"; }
  desc_of()     { local d; d="$(frontmatter_field "$1" description)"; [[ -n "$d" ]] || d="$(grep -m1 -v '^[[:space:]]*$' "$1" || true)"; printf '%s: %s\n' "$(basename "$1" .md)" "$d"; }

  local inst n_inst skills n_skills agents n_agents cmds n_cmds name f rows=""
  read -r inst n_inst < <(sum_segment "$claude_dir/CLAUDE.md" "$claude_dir"/rules/*.md)
  # Skills: one weight per skill (kept for the "heaviest" list), summed below.
  while IFS= read -r name; do
    [[ -n "$name" ]] && skill_exists "$name" || continue
    rows+="$(est_tokens "$name: $(skill_description "$name")")"$'\t'"$name"$'\n'
  done < <(all_skill_names)
  read -r skills n_skills < <(printf '%s' "$rows" | awk -F'\t' '{ t += $1; n++ } END { print t+0, n+0 }')
  read -r agents n_agents < <(for f in "$claude_dir"/agents/*.md; do [[ -f "$f" ]] && desc_of "$f"; done | sum_descs)
  read -r cmds n_cmds < <(for f in "$claude_dir"/commands/*.md; do [[ -f "$f" ]] && desc_of "$f"; done | sum_descs)
  local total=$((inst + skills + agents + cmds))

  printf 'context budget (tokens ≈ chars/4; always-loaded segments from this repo)\n'
  printf '  %-34s %6d  (%d files)\n' "CLAUDE.md + rules/*.md" "$inst" "$n_inst"
  printf '  %-34s %6d  (%d skills)\n' "skill name+description" "$skills" "$n_skills"
  printf '  %-34s %6d  (%d agents)\n' "agent name+description" "$agents" "$n_agents"
  printf '  %-34s %6d  (%d commands)\n' "command name+description" "$cmds" "$n_cmds"
  printf '  %-34s %6d  limit %d (%d%%)\n' "TOTAL" "$total" "$limit" $(( total * 100 / limit ))
  if [[ "$top" -gt 0 && -n "$rows" ]]; then
    printf '  heaviest skill descriptions:\n'
    printf '%s' "$rows" | sort -rn | head -n "$top" | awk -F'\t' '{ printf "    %5d  %s\n", $1, $2 }'
  fi
  if [[ "$total" -gt "$limit" ]]; then
    err "budget: always-loaded context is $total tokens, over the $limit-token limit (trim descriptions, drop unused skills, or raise CONTEXT_BUDGET_TOKENS deliberately)"
    [[ "$check" -eq 1 ]] && return 1
  fi
  return 0
}

cmd_doctor() {
  local issues=0 name sidecar md desc
  flag() { printf '%s\n' "$*"; issues=$((issues + 1)); }

  if [[ "$KIND" == "skill" ]]; then
    # Vendored skills: validate the manifest. Their files may be un-materialized.
    if [[ ! -f "$MANIFEST" ]]; then
      flag "$(rel "$MANIFEST"): missing"
    elif ! jq -e 'type == "array"' "$MANIFEST" >/dev/null 2>&1; then
      flag "$(rel "$MANIFEST"): not a JSON array"
    else
      local dup f
      dup="$(manifest_names | sort | uniq -d)"
      [[ -z "$dup" ]] || flag "manifest: duplicate skill name(s): $(printf '%s' "$dup" | tr '\n' ' ')"
      while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        local entry; entry="$(manifest_entry "$name")"
        for f in repo subpath ref commit category description; do
          [[ -n "$(jq -r --arg f "$f" '.[$f] // ""' <<<"$entry")" ]] \
            || flag "$name: manifest entry missing '$f'"
        done
        grep -qxF "/skills/$name/" "$GITIGNORE" 2>/dev/null \
          || flag "$name: vendored dir not listed in .gitignore managed block"
      done < <(manifest_names)
    fi
    # Authored / unmanaged skills: dirs not in the manifest.
    local dir
    for dir in "$RESOURCE_ROOT"/*/; do
      [[ -d "$dir" ]] || continue
      name="$(basename "$dir")"
      is_vendored "$name" && continue
      md="$dir/SKILL.md"
      [[ -f "$md" ]] || { flag "$name: missing $(rel "$md")"; continue; }
      [[ -n "$(frontmatter_field "$md" name)" ]] || flag "$name: SKILL frontmatter has no 'name'"
      [[ -n "$(frontmatter_field "$md" description)" ]] || flag "$name: frontmatter has no 'description'"
      # Optional golden-task evals (skill-creator shape): validate when present.
      if [[ -f "$dir/evals/evals.json" ]] && ! jq -e --arg n "$name" '
            type == "object" and (.skill_name == $n)
            and (.evals | type == "array" and length > 0)
            and all(.evals[]; (.name|type=="string") and (.prompt|type=="string") and (.expected_output|type=="string"))
            and ((.evals | map(.name) | length) == (.evals | map(.name) | unique | length))
          ' "$dir/evals/evals.json" >/dev/null 2>&1; then
        flag "$name: evals/evals.json malformed (want {skill_name: \"$name\", evals: [{name, prompt, expected_output, files?}, ...]} with unique names)"
      fi
      sidecar="$dir.source.json"
      if [[ ! -f "$sidecar" ]]; then
        flag "$name: unmanaged (no .source.json sidecar)"
      elif [[ "$(jq -r '.repo // "null"' "$sidecar")" != "null" ]]; then
        flag "$name: stale vendored dir (sidecar names a repo but not in $(rel "$MANIFEST")); prune with 'make skills-materialize' or re-add with 'make skills-fetch'"
      elif [[ "$(jq -r '.category // ""' "$sidecar")" == "" ]]; then
        flag "$name: sidecar has no 'category'"
      fi
    done
    # Scan baselines must name a live skill (skills-delete removes them; catch drift).
    local bl bname
    for bl in "$SCAN_BASELINE_DIR"/*.json; do
      [[ -f "$bl" ]] || continue
      bname="$(basename "$bl" .json)"
      [[ "$bname" == _* ]] && continue
      skill_exists "$bname" || flag "$(rel "$bl"): scan baseline for '$bname', which is not a skill (delete it, or restore the skill)"
    done
    cmd_catalog --check || issues=$((issues + 1))
    cmd_suites --check || issues=$((issues + 1))
    cmd_budget --check --top 0 >/dev/null || issues=$((issues + 1))
  else
    while IFS=$'\t' read -r name sidecar; do
      [[ -n "$name" ]] || continue
      md="$RESOURCE_ROOT/$name.md"
      if [[ ! -f "$md" ]]; then
        flag "$name: missing $(rel "$md")"
        continue
      fi
      [[ -n "$(frontmatter_field "$md" name)" ]] || flag "$name: agent frontmatter has no 'name'"
      desc="$(frontmatter_field "$md" description)"
      [[ -n "$desc" ]] || flag "$name: frontmatter has no 'description'"
      if [[ ! -f "$sidecar" ]]; then
        flag "$name: unmanaged (no .source.json sidecar)"
      elif [[ "$(jq -r '.category // ""' "$sidecar")" == "" ]]; then
        flag "$name: sidecar has no 'category'"
      fi
    done < <(iter_resources)
  fi

  if [[ "$issues" -gt 0 ]]; then
    err "doctor: $issues issue(s) found"
    return 1
  fi
  info "doctor: all ${KIND}s healthy"
}

# Set/replace the category on an existing resource's sidecar (in place, so it
# survives update). Creates a minimal local sidecar if none exists yet.
cmd_category() {
  local name="" category=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)     name="$2"; shift 2 ;;
      --category) category="$2"; shift 2 ;;
      *) die "category: unknown argument '$1'" ;;
    esac
  done
  [[ -n "$name"     ]] || die "category: --name NAME is required"
  [[ -n "$category" ]] || die "category: --category CAT is required"
  if [[ "$KIND" == "skill" ]] && is_vendored "$name"; then
    manifest_set_category "$name" "$category"
    info "$name: category set to '$category'"
    return 0
  fi
  local artifact sidecar
  artifact="$(artifact_path "$name")"
  sidecar="$(sidecar_path "$name")"
  [[ -e "$artifact" ]] || die "$name: no such $KIND"
  if [[ -f "$sidecar" ]]; then
    local tmp; tmp="$(mktemp)"
    jq --arg c "$category" '.category = $c' "$sidecar" > "$tmp" && mv "$tmp" "$sidecar"
  else
    jq -n --arg c "$category" '{repo:null, category:$c}' > "$sidecar"
  fi
  info "$name: category set to '$category'"
}

# --- dispatch --------------------------------------------------------------

[[ $# -ge 2 && "$1" == "--kind" ]] \
  || die "usage: resource-manager.sh --kind {skill|agent} {fetch|list|update|delete} ..."
KIND="$2"; shift 2
configure_kind

[[ $# -ge 1 ]] || die "missing command (expected fetch|materialize|list|update|delete)"
cmd="$1"; shift
case "$cmd" in
  fetch)       cmd_fetch       "$@" ;;
  materialize) cmd_materialize "$@" ;;
  sync-gitignore) [[ "$KIND" == "skill" ]] || die "sync-gitignore: skill only"; sync_gitignore; info "synced .gitignore vendored-skills block" ;;
  list)        cmd_list        "$@" ;;
  update)      cmd_update      "$@" ;;
  delete)      cmd_delete      "$@" ;;
  category)    cmd_category    "$@" ;;
  catalog)     cmd_catalog     "$@" ;;
  suites)      cmd_suites      "$@" ;;
  budget)      cmd_budget      "$@" ;;
  doctor)      cmd_doctor      "$@" ;;
  *) die "unknown command '$cmd' (expected fetch|materialize|list|update|delete|category|catalog|suites|budget|doctor)" ;;
esac
