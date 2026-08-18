#!/usr/bin/env python3
"""PreToolUse safety gate for Claude Code.

A deterministic deny/ask layer that runs before dispatch, so the ABSOLUTE rules
in claude/CLAUDE.md and rules/git-hygiene.md do not depend on the model reading
and obeying prose. Mirrors the pi extensions permission-gate.ts (dangerous bash)
and protected-paths.ts (writes to .env / .git / node_modules) for the Claude side.

Every deny/ask is appended to $CLAUDE_CONFIG_DIR/safety-guard.log — a denied
call is a signal to go find what asked for it, not only a blocked call.

Wired per-profile in settings.json (not tracked in this repo):
  {"hooks":{"PreToolUse":[
    {"matcher":"Bash","hooks":[{"type":"command","command":"python3 $CLAUDE_CONFIG_DIR/scripts/safety-guard-hook.py","timeout":10}]},
    {"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"python3 $CLAUDE_CONFIG_DIR/scripts/safety-guard-hook.py","timeout":10}]}
  ]}}

Decisions:
  deny — hard block; the model gets the reason and must find another way.
  ask  — the user is prompted (rules that say "unless explicitly asked").
Edit the RULES tables below, not the logic. Test: scripts/test-safety-guard-hook.py
Stdlib only, Python 3.9+.
"""
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# A "word" boundary that also excludes - and _ (so "git-rm" and "sudoku" don't match).
W = r"(?<![A-Za-z0-9_-])"
# Anything up to the next ; & | — keeps a match inside one shell command.
SEG = r"(?:[^;&|]*\s)?"
END = r"(?=[\s;&|]|$)"
# rm's recursive flag in any of its spellings (-r, -R, -rf, -fr, --recursive).
RECURSIVE = r"(?:-[A-Za-z]*[rR][A-Za-z]*|--recursive)"


def rx(pattern: str) -> re.Pattern:
    return re.compile(pattern, re.VERBOSE)


# --- Bash: deny outright -------------------------------------------------------
BASH_DENY = [
    ("privilege escalation", rx(rf"{W} sudo {END}")),
    ("world-writable chmod/chown", rx(rf"{W} (?:chmod|chown) \s+ {SEG} [0-7]?777 {END}")),
    ("rm -rf on / ~ $HOME .git", rx(
        rf"{W} rm \s+ {SEG} {RECURSIVE} \s+ {SEG}"
        rf"(?:/|~|\$HOME|\$\{{HOME\}}|\.git) /? \*? \s* (?:[;&|]|$)")),
    ("git add -A / --all / .", rx(rf"{W} git \s+ {SEG} add \s+ {SEG} (?:-A|--all|\.) {END}")),
]

# --- Bash: ask the user --------------------------------------------------------
BASH_ASK = [
    ("recursive rm", rx(rf"{W} rm \s+ {SEG} {RECURSIVE} {END}")),
    ("force-push", rx(rf"{W} git \s+ {SEG} push \s+ {SEG} (?:-f|--force|--force-with-lease) {END}")),
    ("discard work (reset --hard / clean -f)", rx(
        rf"{W} git \s+ {SEG} (?: reset \s+ {SEG} --hard | clean \s+ {SEG} -[A-Za-z]*[fF] )")),
]

# --- Edit/Write: protected paths -----------------------------------------------
# Basename .env or .env.<anything> (PATH_ALLOW carves out committed templates);
# anything under a .git/ or node_modules/ directory.
PATH_DENY = [
    ("secrets file", rx(r"(?:^|/) \.env (?:\.[^/]*)? $")),
    ("VCS internals", rx(r"(?:^|/) \.git (?:/|$)")),
    ("vendored dependencies", rx(r"(?:^|/) node_modules (?:/|$)")),
]
PATH_ALLOW = [rx(r"(?:^|/) \.env \. (?:example|sample|template|dist) $")]

WRITE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
LOG_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))


def decide(tool: str, tool_input: dict) -> "tuple[str, str, str] | None":
    """Return (decision, reason, subject) or None to allow silently."""
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if not cmd:
            return None
        # "git rm" is index bookkeeping, not a filesystem rm; keep it out of the rm rules.
        norm = re.sub(r"git\s+rm", "git-rm", cmd)
        for label, pat in BASH_DENY:
            if pat.search(norm):
                return ("deny", f"safety-guard: hard-deny — {label}. See rules/git-hygiene.md and claude/CLAUDE.md.", cmd)
        for label, pat in BASH_ASK:
            if pat.search(norm):
                return ("ask", f"safety-guard: {label} — destructive or history-rewriting; needs explicit user approval.", cmd)
        return None
    if tool in WRITE_TOOLS:
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if not path or any(p.search(path) for p in PATH_ALLOW):
            return None
        for label, pat in PATH_DENY:
            if pat.search(path):
                return ("deny", f"safety-guard: write to protected path blocked ({label}) — secrets and VCS/vendor internals are never edited by the agent.", path)
    return None


def log(decision: str, tool: str, reason: str, subject: str) -> None:
    try:
        with open(LOG_DIR / "safety-guard.log", "a", encoding="utf-8") as fh:
            fh.write(f"{datetime.now():%Y-%m-%dT%H:%M:%S} decision={decision} tool={tool} reason={reason} subject={subject[:200]}\n")
    except OSError:
        pass  # logging must never block the gate


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    tool = payload.get("tool_name") or ""
    verdict = decide(tool, payload.get("tool_input") or {})
    if verdict is None:
        return 0
    decision, reason, subject = verdict
    log(decision, tool, reason, subject)
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
