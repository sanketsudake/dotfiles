#!/usr/bin/env python3
"""Table-driven test for packages/claude/scripts/safety-guard-hook.py.

Each case: (tool, tool_input, expected decision). Runs the hook as a subprocess
with a stock PATH and a temp CLAUDE_CONFIG_DIR, exactly as Claude Code would.
Run: python3 scripts/test-safety-guard-hook.py   (also picked up by CI)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parent.parent / "packages" / "claude" / "scripts" / "safety-guard-hook.py"

CASES = [
    # --- Bash: deny
    ("Bash", {"command": "sudo apt install x"}, "deny"),
    ("Bash", {"command": "chmod 777 file"}, "deny"),
    ("Bash", {"command": "chmod -R 0777 dir"}, "deny"),
    ("Bash", {"command": "chown -R 777 dir"}, "deny"),
    ("Bash", {"command": "rm -rf /"}, "deny"),
    ("Bash", {"command": "rm -rf /*"}, "deny"),
    ("Bash", {"command": "rm -rf ~"}, "deny"),
    ("Bash", {"command": "rm -rf ~/"}, "deny"),
    ("Bash", {"command": "rm -rf $HOME"}, "deny"),
    ("Bash", {"command": "rm -rf ${HOME}/"}, "deny"),
    ("Bash", {"command": "rm -rf .git"}, "deny"),
    ("Bash", {"command": "rm -fr .git/"}, "deny"),
    ("Bash", {"command": "cd repo && rm -rf .git"}, "deny"),
    ("Bash", {"command": 'rm -rf "$HOME"'}, "deny"),
    ("Bash", {"command": "rm -rf '~'"}, "deny"),
    ("Bash", {"command": 'rm -rf "/"'}, "deny"),
    ("Bash", {"command": "rm -rf ./.git"}, "deny"),
    ("Bash", {"command": "mygit rm -rf ~"}, "deny"),
    ("Bash", {"command": "git add -Av"}, "deny"),
    ("Bash", {"command": "git add -vA ."}, "deny"),
    ("Bash", {"command": "git add -A"}, "deny"),
    ("Bash", {"command": "git add --all"}, "deny"),
    ("Bash", {"command": "git add . && git commit -m x"}, "deny"),
    ("Bash", {"command": "git add README.md ."}, "deny"),
    ("Bash", {"command": "git -C sub add -A"}, "deny"),
    ("Bash", {"command": "cd x; git add -A"}, "deny"),
    # --- Bash: ask
    ("Bash", {"command": "rm -rf build/"}, "ask"),
    ("Bash", {"command": "rm -r tmpdir; ls"}, "ask"),
    ("Bash", {"command": "rm -Rf ~/scratch/x"}, "ask"),
    ("Bash", {"command": "rm --recursive out"}, "ask"),
    ("Bash", {"command": "git push --force origin feat"}, "ask"),
    ("Bash", {"command": "git push origin feat -f"}, "ask"),
    ("Bash", {"command": "git push --force-with-lease"}, "ask"),
    ("Bash", {"command": "git push --force-with-lease=origin/main"}, "ask"),
    ("Bash", {"command": "legit rm -rf /tmp/x"}, "ask"),
    ("Bash", {"command": "mygit rm -rf ~/data"}, "ask"),
    ("Bash", {"command": "backup-git rm -r out/"}, "ask"),
    ("Bash", {"command": "git reset --hard HEAD~1"}, "ask"),
    ("Bash", {"command": "git clean -fd"}, "ask"),
    ("Bash", {"command": "git clean -xdf"}, "ask"),
    # --- Bash: allow
    ("Bash", {"command": "ls ~/sudoku"}, "allow"),
    ("Bash", {"command": "chmod 644 file && echo 777"}, "allow"),
    ("Bash", {"command": "chmod +x script.sh"}, "allow"),
    ("Bash", {"command": "rm file.txt"}, "allow"),
    ("Bash", {"command": "rm -f a b"}, "allow"),
    ("Bash", {"command": "git rm -r --cached skills/x"}, "allow"),
    ("Bash", {"command": "cd x && git rm -rf old/"}, "allow"),
    ("Bash", {"command": "git add -p src/"}, "allow"),
    ("Bash", {"command": "git add -u"}, "allow"),
    ("Bash", {"command": "git add README.md"}, "allow"),
    ("Bash", {"command": "git add ./scripts/x.sh"}, "allow"),
    ("Bash", {"command": "git push -u origin feat"}, "allow"),
    ("Bash", {"command": "git reset --soft HEAD~1"}, "allow"),
    ("Bash", {"command": "grep -r foo ."}, "allow"),
    ("Bash", {"command": "docker rm -f ctr"}, "allow"),
    ("Bash", {"command": "npm rm -g pkg"}, "allow"),
    ("Bash", {"command": "echo sudoers"}, "allow"),
    ("Bash", {"command": ""}, "allow"),
    # --- Edit/Write: deny
    ("Write", {"file_path": "/repo/.env"}, "deny"),
    ("Write", {"file_path": "/repo/.env.local"}, "deny"),
    ("Edit", {"file_path": "/repo/.env.production"}, "deny"),
    ("Edit", {"file_path": "/repo/.git/hooks/pre-commit"}, "deny"),
    ("Edit", {"file_path": ".git/config"}, "deny"),
    ("MultiEdit", {"file_path": "/repo/node_modules/x/index.js"}, "deny"),
    # --- Edit/Write: allow
    ("Edit", {"file_path": "/repo/.env.example"}, "allow"),
    ("Edit", {"file_path": "/repo/.env.sample"}, "allow"),
    ("Edit", {"file_path": "/repo/.envrc"}, "allow"),
    ("Edit", {"file_path": "/repo/config/environment.env.yaml"}, "allow"),
    ("Edit", {"file_path": "/repo/.github/workflows/ci.yml"}, "allow"),
    ("Edit", {"file_path": "/repo/.gitignore"}, "allow"),
    ("NotebookEdit", {"notebook_path": "/repo/nb.ipynb"}, "allow"),
    # --- other tools: never touched
    ("Read", {"file_path": "/repo/.env"}, "allow"),
    ("Agent", {"prompt": "rm -rf /"}, "allow"),
]


def run_hook(stdin_text: str, config_dir: str) -> str:
    env = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": os.environ.get("HOME", "/tmp"),
           "CLAUDE_CONFIG_DIR": config_dir}
    proc = subprocess.run([sys.executable, str(HOOK)], input=stdin_text, capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        raise AssertionError(f"hook exited {proc.returncode}: {proc.stderr}")
    if not proc.stdout.strip():
        return "allow"
    return json.loads(proc.stdout)["hookSpecificOutput"]["permissionDecision"]


class SafetyGuardCases(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_table(self):
        failures = []
        for tool, tool_input, expected in CASES:
            got = run_hook(json.dumps({"tool_name": tool, "tool_input": tool_input}), self.tmp.name)
            if got != expected:
                failures.append(f"want={expected:<5} got={got:<5} {tool} {tool_input}")
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_garbage_input_is_allowed_silently(self):
        self.assertEqual(run_hook("not json", self.tmp.name), "allow")

    def test_decisions_are_logged(self):
        run_hook(json.dumps({"tool_name": "Bash", "tool_input": {"command": "sudo id"}}), self.tmp.name)
        log = Path(self.tmp.name) / "safety-guard.log"
        self.assertTrue(log.exists())
        self.assertIn("decision=deny tool=Bash", log.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=1)
