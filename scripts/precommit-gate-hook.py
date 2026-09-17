#!/usr/bin/env python3
"""Project-scoped PreToolUse hook (wired in this repo's .claude/settings.json).

When the agent runs a `git commit` that targets this repo (or a worktree of
it), run the repo's pre-flight gate in that checkout first and block the commit
(exit 2, stderr goes back to the model) if the gate fails. Commits to any other
repo pass through: a session started here often commits elsewhere (e.g. a
notes vault), and this repo's preflight says nothing about those.

The target repo is found the way git would find it: `-C <dir>` on the git
command, else the last `cd <dir>` before it in the same command, else the hook
input's `cwd` (then CLAUDE_PROJECT_DIR). It counts as this repo when its git
common dir matches ours. A commit whose target cannot be resolved is gated
(fail closed), as is a command the shell lexer cannot split.

The same checks run in CI (.github/workflows/checks.yml); this catches them
before the commit exists instead of after the push.
PRECOMMIT_GATE_CMD overrides the gate command (default: make -s preflight);
scripts/test-precommit-gate-hook.py uses it.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
GATE_CMD = os.environ.get("PRECOMMIT_GATE_CMD", "make -s preflight")
COMMIT_RE = re.compile(r"(^|[^A-Za-z0-9_-])git(\s+[^;&|]*)?\s+commit(\s|$)")
ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# git global options that take their value as the next word
GIT_OPTS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
SHELLS = {"bash", "sh", "zsh", "dash"}
UNRESOLVED = object()


def resolve(path: str, base: str) -> str:
    path = os.path.expandvars(os.path.expanduser(path))
    return os.path.normpath(os.path.join(base, path))


def segments(command: str):
    """Split a shell command into simple commands (lists of words).

    Subshell parentheses are yielded as the strings "(" and ")" so a `cd`
    inside them can be scoped.
    """
    lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    seg: list[str] = []
    for tok in lexer:
        if tok and set(tok) <= set("();|&"):
            if seg:
                yield seg
            seg = []
            yield from (c for c in tok if c in "()")
        else:
            seg.append(tok)
    if seg:
        yield seg


def commit_targets(command: str, cwd: str) -> list:
    """Return (dir, git_dir) for every `git commit` in the command."""
    targets = []
    saved: list[str] = []
    for words in segments(command):
        if words == "(":
            saved.append(cwd)
            continue
        if words == ")":
            cwd = saved.pop() if saved else cwd
            continue
        while words and (ENV_ASSIGN.match(words[0]) or words[0] in ("command", "env", "exec", "time", "nohup")):
            words = words[1:]
        if not words:
            continue
        prog = os.path.basename(words[0])
        if prog in ("cd", "pushd"):
            args = [w for w in words[1:] if not w.startswith("-")]
            cwd = resolve(args[0], cwd) if args else os.path.expanduser("~")
        elif prog in SHELLS:
            for i, w in enumerate(words[1:-1], start=1):
                if re.fullmatch(r"-[a-z]*c[a-z]*", w):
                    targets += commit_targets(words[i + 1], cwd)
                    break
        elif prog == "eval":
            targets += commit_targets(" ".join(words[1:]), cwd)
        elif prog == "git":
            target, git_dir, i = cwd, None, 1
            while i < len(words) and words[i].startswith("-"):
                opt = words[i]
                if opt in GIT_OPTS_WITH_ARG and i + 1 < len(words):
                    if opt == "-C":
                        target = resolve(words[i + 1], target)
                    elif opt == "--git-dir":
                        git_dir = resolve(words[i + 1], target)
                    i += 2
                    continue
                if opt.startswith("--git-dir="):
                    git_dir = resolve(opt.split("=", 1)[1], target)
                i += 1
            if i < len(words) and words[i] == "commit":
                targets.append((target, git_dir))
    return targets


def repo_of(target: str, git_dir: str | None):
    """Return (common_dir, toplevel) for a checkout, or UNRESOLVED."""
    if not os.path.isdir(target):
        return UNRESOLVED
    cmd = ["git", "-C", target]
    if git_dir:
        cmd += ["--git-dir", git_dir]
    cmd += ["rev-parse", "--git-common-dir", "--show-toplevel"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    lines = res.stdout.splitlines()
    if res.returncode != 0 or len(lines) != 2:
        return UNRESOLVED
    common, top = lines
    return os.path.realpath(os.path.join(target, common)), os.path.realpath(top)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    command = (payload.get("tool_input") or {}).get("command") or ""
    if not COMMIT_RE.search(command):
        return 0
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    notes = []
    try:
        targets = commit_targets(command, cwd)
    except ValueError:
        targets = [(None, None)]
        notes.append("precommit-gate: could not parse the command; gating it as a commit to this repo.")

    ours = repo_of(ROOT, None)
    gate_dirs: list[str] = []
    for target, git_dir in targets:
        repo = repo_of(target, git_dir) if target else UNRESOLVED
        if repo is UNRESOLVED or ours is UNRESOLVED:
            if target:
                notes.append(f"precommit-gate: could not resolve the target repo of `git -C {target} commit`; gating it as a commit to this repo.")
            checkout = ROOT
        elif repo[0] == ours[0]:
            checkout = repo[1]
        else:
            continue
        if checkout not in gate_dirs:
            gate_dirs.append(checkout)

    for checkout in gate_dirs:
        res = subprocess.run(GATE_CMD, shell=True, cwd=checkout, capture_output=True, text=True)
        if res.returncode != 0:
            print("\n".join(notes + [
                "precommit-gate: pre-flight gate failed; fix before committing:",
                (res.stdout + res.stderr).rstrip(),
                "(run: make preflight)",
            ]), file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
