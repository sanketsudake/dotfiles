#!/usr/bin/env python3
"""Table-driven test for the Antigravity safety gate.

Each case: (tool, args, expected decision). Runs
packages/antigravity/plugins/dotfiles-harness/scripts/safety-guard-hook.py as a
subprocess with the payload shape Antigravity sends on stdin
({"toolCall": {"name", "args"}}), and a temp HOME so the hook's log stays out
of the real one.
Run: python3 scripts/test-antigravity-safety-guard-hook.py   (also picked up by CI)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HOOK = (
    Path(__file__).resolve().parent.parent
    / "packages"
    / "antigravity"
    / "plugins"
    / "dotfiles-harness"
    / "scripts"
    / "safety-guard-hook.py"
)

CASES = [
    # --- run_command: deny
    ("run_command", {"CommandLine": "sudo apt install x"}, "deny"),
    ("run_command", {"CommandLine": "chmod 777 file"}, "deny"),
    ("run_command", {"CommandLine": "chmod -R 0777 dir"}, "deny"),
    ("run_command", {"CommandLine": "chown -R 777 dir"}, "deny"),
    ("run_command", {"CommandLine": "rm -rf /"}, "deny"),
    ("run_command", {"CommandLine": "rm -rf /*"}, "deny"),
    ("run_command", {"CommandLine": "rm -rf ~"}, "deny"),
    ("run_command", {"CommandLine": "rm -rf ~/"}, "deny"),
    ("run_command", {"CommandLine": "rm -rf $HOME"}, "deny"),
    ("run_command", {"CommandLine": "rm -rf ${HOME}/"}, "deny"),
    ("run_command", {"CommandLine": "rm -rf .git"}, "deny"),
    ("run_command", {"CommandLine": "rm -fr .git/"}, "deny"),
    ("run_command", {"CommandLine": "cd repo && rm -rf .git"}, "deny"),
    ("run_command", {"CommandLine": 'rm -rf "$HOME"'}, "deny"),
    ("run_command", {"CommandLine": "rm -rf ./.git"}, "deny"),
    ("run_command", {"CommandLine": "git add -Av"}, "deny"),
    ("run_command", {"CommandLine": "git add -A"}, "deny"),
    ("run_command", {"CommandLine": "git add --all"}, "deny"),
    ("run_command", {"CommandLine": "git add . && git commit -m x"}, "deny"),
    ("run_command", {"CommandLine": "git add README.md ."}, "deny"),
    ("run_command", {"CommandLine": "git -C sub add -A"}, "deny"),
    # --- run_command: ask
    ("run_command", {"CommandLine": "rm -rf build/"}, "ask"),
    ("run_command", {"CommandLine": "rm -r tmpdir; ls"}, "ask"),
    ("run_command", {"CommandLine": "rm --recursive out"}, "ask"),
    ("run_command", {"CommandLine": "git push --force origin feat"}, "ask"),
    ("run_command", {"CommandLine": "git push --force-with-lease=origin/main"}, "ask"),
    ("run_command", {"CommandLine": "git reset --hard HEAD~1"}, "ask"),
    ("run_command", {"CommandLine": "git clean -fd"}, "ask"),
    # --- run_command: allow
    ("run_command", {"CommandLine": "ls ~/sudoku"}, "allow"),
    ("run_command", {"CommandLine": "chmod 644 file && echo 777"}, "allow"),
    ("run_command", {"CommandLine": "rm file.txt"}, "allow"),
    ("run_command", {"CommandLine": "git rm -r --cached skills/x"}, "allow"),
    ("run_command", {"CommandLine": "git add -p src/"}, "allow"),
    ("run_command", {"CommandLine": "git push -u origin feat"}, "allow"),
    ("run_command", {"CommandLine": "git reset --soft HEAD~1"}, "allow"),
    ("run_command", {"CommandLine": ""}, "allow"),
    # --- write_file/edit_file: deny (TargetFile is the argument the tools use)
    ("write_file", {"TargetFile": "/repo/.env", "CodeContent": "x"}, "deny"),
    ("write_file", {"TargetFile": "/repo/.env.local"}, "deny"),
    ("edit_file", {"TargetFile": "/repo/.env.production"}, "deny"),
    ("edit_file", {"TargetFile": "/repo/.git/hooks/pre-commit"}, "deny"),
    ("edit_file", {"TargetFile": ".git/config"}, "deny"),
    ("write_file", {"TargetFile": "/repo/node_modules/x/index.js"}, "deny"),
    # --- write_file/edit_file: allow
    ("edit_file", {"TargetFile": "/repo/.env.example"}, "allow"),
    ("edit_file", {"TargetFile": "/repo/.env.sample"}, "allow"),
    ("edit_file", {"TargetFile": "/repo/.envrc"}, "allow"),
    ("edit_file", {"TargetFile": "/repo/config/environment.env.yaml"}, "allow"),
    ("edit_file", {"TargetFile": "/repo/.gitignore"}, "allow"),
    # --- other tools: never touched
    ("read_file", {"Path": "/repo/.env"}, "allow"),
    ("grep_search", {"Query": "rm -rf /"}, "allow"),
]


def run_hook(payload: str, home: str) -> str:
    env = {
        "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
        "HOME": home,
    }
    proc = subprocess.run(
        [sys.executable, str(HOOK)], input=payload, capture_output=True, text=True, env=env
    )
    if proc.returncode != 0:
        raise AssertionError(f"hook exited {proc.returncode}: {proc.stderr}")
    return json.loads(proc.stdout)["decision"]


class AntigravitySafetyGuardCases(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_table(self):
        failures = []
        for tool, args, expected in CASES:
            payload = json.dumps({"toolCall": {"id": "toolu_01", "name": tool, "args": args}})
            got = run_hook(payload, self.tmp.name)
            if got != expected:
                failures.append(f"want={expected:<5} got={got:<5} {tool} {args}")
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_garbage_input_is_allowed_silently(self):
        self.assertEqual(run_hook("not json", self.tmp.name), "allow")

    def test_decisions_are_logged(self):
        payload = json.dumps(
            {"toolCall": {"id": "toolu_01", "name": "run_command", "args": {"CommandLine": "sudo id"}}}
        )
        run_hook(payload, self.tmp.name)
        log = Path(self.tmp.name) / ".gemini" / "antigravity-cli" / "safety-guard.log"
        self.assertTrue(log.exists())
        self.assertIn("DENY:", log.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=1)
