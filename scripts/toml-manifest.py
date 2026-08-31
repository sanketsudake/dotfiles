#!/usr/bin/env python3
"""toml-manifest.py — read/write the repo's sources.toml manifest.

The manifest is the single committed record of every skill and agent
source: two arrays of tables, [[skill]] and [[agent]], each entry at
least {name}, plus {repo, subpath, ref, commit} when vendored and
optional {category, description, fetched_at, note}.

Commands (stdin/stdout are JSON; the TOML file is the argument):
  to-json   <sources.toml>   print {"skill": [...], "agent": [...]}
  from-json <sources.toml>   read the same JSON on stdin, write the file

The writer is deterministic — fixed key order, entries sorted by name,
one key per line — so a round-trip of an untouched manifest is
byte-identical and diffs stay per-entry. Stdlib only (tomllib, py>=3.11).
"""
import json
import sys
import tomllib

KINDS = ("skill", "agent")
KEY_ORDER = ("name", "repo", "subpath", "ref", "commit", "fetched_at", "category", "description", "note")


def die(msg: str) -> None:
    print(f"toml-manifest: {msg}", file=sys.stderr)
    raise SystemExit(1)


def toml_str(s: str) -> str:
    if any(c in s for c in "\\\"\n\t"):
        return json.dumps(s)  # JSON string escapes are valid TOML basic-string escapes
    return f'"{s}"'


def to_json(path: str) -> None:
    try:
        with open(path, "rb") as fh:
            doc = tomllib.load(fh)
    except FileNotFoundError:
        doc = {}
    out = {k: doc.get(k, []) for k in KINDS}
    json.dump(out, sys.stdout)
    print()


def from_json(path: str) -> None:
    doc = json.load(sys.stdin)
    lines = [
        "# sources.toml — the single manifest of every skill and agent source.",
        "# Managed by scripts/resource-manager.sh (make skills-* / agents-*);",
        "# an entry with repo+commit is vendored (skill files gitignored,",
        "# materialized from the pin), one without repo is authored here.",
    ]
    for kind in KINDS:
        entries = doc.get(kind) or []
        for entry in sorted(entries, key=lambda e: e.get("name", "")):
            lines.append("")
            lines.append(f"[[{kind}]]")
            for key in KEY_ORDER:
                val = entry.get(key)
                if val is None or val == "":
                    continue
                if not isinstance(val, str):
                    die(f"{kind} '{entry.get('name')}': field '{key}' must be a string")
                lines.append(f"{key} = {toml_str(val)}")
            extra = set(entry) - set(KEY_ORDER) - {"repo"}
            extra = {k for k in extra if entry[k] not in (None, "")}
            if extra:
                die(f"{kind} '{entry.get('name')}': unknown fields {sorted(extra)}")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in ("to-json", "from-json"):
        die("usage: toml-manifest.py {to-json|from-json} <sources.toml>")
    (to_json if sys.argv[1] == "to-json" else from_json)(sys.argv[2])


if __name__ == "__main__":
    main()
