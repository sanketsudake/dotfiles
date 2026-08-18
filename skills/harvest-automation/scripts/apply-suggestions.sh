#!/usr/bin/env bash
# apply-suggestions.sh — apply approved harvest-automation suggestions to CLAUDE.md
# and/or memory files. (Skills are NOT applied here — they are handed to the
# superpowers:writing-skills skill, which authors and validates them.)
#
# Usage: apply-suggestions.sh <scope> <payload.json>
#   scope : all | claude | memory
#   payload.json schema:
#     {
#       "claude_md": { "path": "...", "append": "..." },
#       "memory":    { "dir":  "...", "entries": [
#                        { "filename": "...", "content": "...", "index_line": "...",
#                          "action": "create|update|supersede", "supersedes": "<old-filename>" }
#                      ] }
#     }
#   action (default create):
#     create    — write a new file; skipped if the filename already exists.
#     update    — replace the existing file's content (backed up to <file>.bak.<ts>)
#                 and its MEMORY.md line; the file must exist.
#     supersede — write the new file and retire the file named in "supersedes"
#                 (backed up, removed, its MEMORY.md line dropped). A contradiction
#                 becomes an update or a supersede, never a second entry.
#   Every memory write stamps `metadata.modified: YYYY-MM-DD` in the frontmatter.
#
# Safety:
#   - CLAUDE.md is backed up to CLAUDE.md.bak.<ts> before every write.
#   - CLAUDE.md is only ever appended to.
#   - Refuses to touch CLAUDE.md if it has >100 lines of uncommitted diff
#     AND is inside a git repo (protects mid-edit work). Override with HARVEST_FORCE=1.
#   - Memory files are only replaced by an explicit update/supersede, with a backup.
#   - Memory index (MEMORY.md) lines are added, replaced, or dropped per entry;
#     duplicate index lines are skipped.

set -euo pipefail

scope="${1:-}"
payload="${2:-}"

if [[ -z "$scope" || -z "$payload" ]]; then
    echo "usage: apply-suggestions.sh <all|claude|memory> <payload.json>" >&2
    exit 2
fi
case "$scope" in
    all|claude|memory) ;;
    *) echo "invalid scope: $scope" >&2; exit 2 ;;
esac
[[ -f "$payload" ]] || { echo "payload not found: $payload" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 2; }

ts=$(date +%Y%m%d%H%M%S)

apply_claude_md() {
    local path append backup diff_lines
    path=$(jq -r '.claude_md.path // empty' "$payload")
    append=$(jq -r '.claude_md.append // empty' "$payload")
    if [[ -z "$path" || -z "$append" ]]; then
        echo "claude: nothing to apply"
        return 0
    fi

    if [[ -f "$path" ]] && git -C "$(dirname "$path")" rev-parse --show-toplevel >/dev/null 2>&1; then
        diff_lines=$(git -C "$(dirname "$path")" diff --numstat -- "$path" 2>/dev/null | awk '{print $1+$2}')
        diff_lines=${diff_lines:-0}
        if (( diff_lines > 100 )) && [[ -z "${HARVEST_FORCE:-}" ]]; then
            echo "claude: refusing — $path has $diff_lines lines of uncommitted diff. Commit first, or re-run with HARVEST_FORCE=1." >&2
            return 1
        fi
    fi

    mkdir -p "$(dirname "$path")"
    if [[ -f "$path" ]]; then
        backup="$path.bak.$ts"
        cp "$path" "$backup"
        echo "claude: backup -> $backup"
        # Ensure a blank line before our append if the file doesn't already end with one.
        if [[ -n "$(tail -c1 "$path")" ]]; then
            printf '\n' >> "$path"
        fi
        printf '\n' >> "$path"
    else
        echo "claude: creating new $path"
    fi
    printf '%s\n' "$append" >> "$path"
    echo "claude: appended $(wc -l <<<"$append" | tr -d ' ') lines to $path"
}

# Stamp (or refresh) `metadata.modified: <today>` inside a memory file's YAML
# frontmatter, adding a metadata block if the file has none. Body is untouched.
stamp_modified() {  # content -> stdout
    local today; today=$(date +%F)
    awk -v today="$today" '
        BEGIN { fm = 0; done = 0 }
        NR == 1 && $0 == "---" { fm = 1; print; next }
        fm == 1 && $0 == "---" {
            if (!done) {
                if (!has_meta) print "metadata:"
                print "  modified: " today
                done = 1
            }
            fm = 2; print; next
        }
        fm == 1 && $0 ~ /^metadata:/ { has_meta = 1; in_meta = 1; print; next }
        fm == 1 && in_meta && $0 ~ /^  modified:/ { if (!done) { print "  modified: " today; done = 1 }; next }
        fm == 1 && in_meta && $0 !~ /^  / {
            if (!done) { print "  modified: " today; done = 1 }
            in_meta = 0
        }
        { print }
    ' <<<"$1"
}

# Drop the MEMORY.md line that links to <filename> (idempotent).
index_drop() {  # index filename
    local tmp; tmp=$(mktemp)
    grep -Fv -- "]($2)" "$1" > "$tmp" || true
    mv "$tmp" "$1"
}

index_add() {  # index line
    grep -Fqx -- "$2" "$1" && return 0
    if [[ -s "$1" && -n "$(tail -c1 "$1")" ]]; then printf '\n' >> "$1"; fi
    printf '%s\n' "$2" >> "$1"
}

apply_memory() {
    local dir entries written skipped index filename content index_line action supersedes
    dir=$(jq -r '.memory.dir // empty' "$payload")
    entries=$(jq -c '.memory.entries // [] | .[]' "$payload")
    if [[ -z "$dir" || -z "$entries" ]]; then
        echo "memory: nothing to apply"
        return 0
    fi

    mkdir -p "$dir"
    index="$dir/MEMORY.md"
    [[ -f "$index" ]] || : > "$index"

    written=0
    skipped=0
    while IFS= read -r entry; do
        filename=$(jq -r '.filename' <<<"$entry")
        content=$(jq -r '.content' <<<"$entry")
        index_line=$(jq -r '.index_line // empty' <<<"$entry")
        action=$(jq -r '.action // "create"' <<<"$entry")
        supersedes=$(jq -r '.supersedes // empty' <<<"$entry")

        case "$action" in
            create)
                if [[ -e "$dir/$filename" ]]; then
                    echo "memory: skip existing $filename (use action=update to replace it)"
                    ((skipped+=1))
                    continue
                fi
                ;;
            update)
                if [[ ! -e "$dir/$filename" ]]; then
                    echo "memory: skip update of missing $filename (use action=create)"
                    ((skipped+=1))
                    continue
                fi
                cp "$dir/$filename" "$dir/$filename.bak.$ts"
                echo "memory: backup -> $dir/$filename.bak.$ts"
                index_drop "$index" "$filename"
                ;;
            supersede)
                if [[ -z "$supersedes" || ! -e "$dir/$supersedes" ]]; then
                    echo "memory: skip supersede of $filename — 'supersedes' missing or names a file that does not exist"
                    ((skipped+=1))
                    continue
                fi
                if [[ -e "$dir/$filename" && "$filename" != "$supersedes" ]]; then
                    echo "memory: skip supersede — $filename already exists (use action=update)"
                    ((skipped+=1))
                    continue
                fi
                cp "$dir/$supersedes" "$dir/$supersedes.bak.$ts"
                rm -f "$dir/$supersedes"
                index_drop "$index" "$supersedes"
                index_drop "$index" "$filename"
                echo "memory: retired $supersedes (backup -> $dir/$supersedes.bak.$ts)"
                ;;
            *)
                echo "memory: skip $filename — unknown action '$action'"
                ((skipped+=1))
                continue
                ;;
        esac

        stamp_modified "$content" > "$dir/$filename"
        ((written+=1))
        [[ -n "$index_line" ]] && index_add "$index" "$index_line"
    done <<<"$entries"

    echo "memory: wrote $written, skipped $skipped — index $index"
}

case "$scope" in
    all)    apply_claude_md; apply_memory ;;
    claude) apply_claude_md ;;
    memory) apply_memory ;;
esac
