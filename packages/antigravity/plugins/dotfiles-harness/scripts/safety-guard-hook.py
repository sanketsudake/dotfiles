#!/usr/bin/env python3
"""PreToolUse safety gate for Antigravity.

A deterministic deny/ask layer that runs before dispatch:
- Blocks privilege escalation (sudo), world-writable chmod/chown (777),
  destructive recursive rm on root/home/vcs, and git add -A / git add .
- Prompts for recursive rm, git push --force, and git reset --hard / clean -f
- Blocks edits/writes to .env (unless template), .git/, and node_modules/

Every deny/ask is logged to ~/.gemini/antigravity-cli/safety-guard.log.
"""
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# Word boundary that also excludes - and _
W = r"(?<![A-Za-z0-9_-])"
SEG = r"(?:[^;&|]*\s)?"
END = r"(?=[\s;&|]|$)"
RECURSIVE = r"(?:-[A-Za-z]*[rR][A-Za-z]*|--recursive)"
Q = r"[\"']?"


def rx(pattern: str) -> re.Pattern:
    return re.compile(pattern, re.VERBOSE)


BASH_DENY = [
    ("privilege escalation", rx(rf"{W} sudo {END}")),
    ("world-writable chmod/chown", rx(rf"{W} (?:chmod|chown) \s+ {SEG} [0-7]?777 {END}")),
    (
        "rm -rf on / ~ $HOME .git",
        rx(
            rf"{W} rm \s+ {SEG} {RECURSIVE} \s+ {SEG}"
            rf"{Q} (?:\./)? (?:/|~|\$HOME|\$\{{HOME\}}|\.git) /? \*? {Q} \s* (?:[;&|]|$)"
        ),
    ),
    (
        "git add -A / --all / .",
        rx(rf"{W} git \s+ {SEG} add \s+ {SEG} (?:-[a-zA-Z]*A[a-zA-Z]*|--all|\.) {END}"),
    ),
]

BASH_ASK = [
    ("recursive rm", rx(rf"{W} rm \s+ {SEG} {RECURSIVE} {END}")),
    (
        "force-push",
        rx(rf"{W} git \s+ {SEG} push \s+ {SEG} (?:-f|--force|--force-with-lease(?:=\S*)?) {END}"),
    ),
    (
        "discard work (reset --hard / clean -f)",
        rx(rf"{W} git \s+ {SEG} (?: reset \s+ {SEG} --hard | clean \s+ {SEG} -[A-Za-z]*[fF] )"),
    ),
]

PATH_DENY = [
    ("secrets file", rx(r"(?:^|/) \.env (?:\.[^/]*)? $")),
    ("VCS internals", rx(r"(?:^|/) \.git (?:/|$)")),
    ("vendored dependencies", rx(r"(?:^|/) node_modules (?:/|$)")),
]
PATH_ALLOW = [rx(r"(?:^|/) \.env \. (?:example|sample|template|dist) $")]


def log_event(decision: str, reason: str, subject: str) -> None:
    log_dir = Path.home() / ".gemini" / "antigravity-cli"
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "safety-guard.log"
        ts = datetime.now().isoformat()
        with log_file.open("a", encoding="utf-8") as f:
            f.write(f"[{ts}] {decision.upper()}: {reason} | subject: {subject}\n")
    except Exception:
        pass


def main() -> None:
    try:
        raw = sys.stdin.read()
        if not raw:
            print(json.dumps({"decision": "allow"}))
            return
        payload = json.loads(raw)
    except Exception:
        print(json.dumps({"decision": "allow"}))
        return

    tool_call = payload.get("toolCall", {})
    tool_name = tool_call.get("name", "")
    args = tool_call.get("args", {})

    if tool_name == "run_command":
        cmd = args.get("CommandLine", "")
        if not cmd:
            print(json.dumps({"decision": "allow"}))
            return
        norm = re.sub(rf"{W}git\s+rm{END}", "git-rm", cmd)
        for label, pat in BASH_DENY:
            if pat.search(norm):
                reason = f"safety-guard: hard-deny — {label}. Follow git-hygiene and safety rules."
                log_event("deny", reason, cmd)
                print(json.dumps({"decision": "deny", "reason": reason}))
                return
        for label, pat in BASH_ASK:
            if pat.search(norm):
                reason = f"safety-guard: {label} — destructive or history-rewriting; needs explicit confirmation."
                log_event("ask", reason, cmd)
                print(json.dumps({"decision": "ask", "reason": reason}))
                return

    elif tool_name in ("write_file", "edit_file"):
        # write_file/edit_file name their argument TargetFile; read_file uses Path.
        path = args.get("TargetFile") or args.get("Path") or ""
        if path and not any(p.search(path) for p in PATH_ALLOW):
            for label, pat in PATH_DENY:
                if pat.search(path):
                    reason = f"safety-guard: protected path — {label} ({path})"
                    log_event("deny", reason, path)
                    print(json.dumps({"decision": "deny", "reason": reason}))
                    return

    print(json.dumps({"decision": "allow"}))


if __name__ == "__main__":
    main()
