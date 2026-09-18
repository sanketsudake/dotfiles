#!/usr/bin/env python3
"""Table-driven test for scripts/precommit-gate-hook.py.

The hook must gate only commits whose target repo is this repo (or one of its
worktrees). Each case builds the hook input exactly as Claude Code sends it and
runs the hook as a subprocess against throwaway git repos: a fake "dotfiles"
repo holding a copy of the hook, a worktree of it, and an unrelated repo.
PRECOMMIT_GATE_CMD stands in for `make -s preflight` (`false` = a red gate).
Run: python3 scripts/test-precommit-gate-hook.py   (also picked up by CI)
Set HOOK=<path> to run the table against another hook implementation.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HOOK = Path(os.environ.get("HOOK", REPO / "scripts" / "precommit-gate-hook.py"))

# (command template, cwd key, gate command, expected exit code)
# Templates use {dot}, {other}, {wt}, {tmp}; cwd keys name the same dirs.
CASES = [
    # not a commit
    ("git status", "dot", "false", 0),
    ("git log --grep commit", "dot", "false", 0),
    ("echo 'git commit'", "dot", "false", 0),
    ("git commit-tree HEAD^{{tree}}", "dot", "false", 0),
    # commits that target the dotfiles repo: gated
    ("git commit -m x", "dot", "false", 2),
    ("git commit -m x", "dot", "true", 0),
    ("git -C {dot} commit -m x", "other", "false", 2),
    ("git -C {dot}/scripts commit -m x", "other", "false", 2),
    ("cd {dot}; git commit -m x", "other", "false", 2),
    ("cd {dot}/scripts && git add a.txt && git commit -m x", "other", "false", 2),
    ("GIT_AUTHOR_NAME=a git commit -m x", "dot", "false", 2),
    ("git -c user.name=a commit -m x", "dot", "false", 2),
    ("bash -c 'git commit -m x'", "dot", "false", 2),
    ("git -C {wt} commit -m x", "other", "false", 2),
    ("(cd {other} && git status); git commit -m x", "dot", "false", 2),
    ("eval 'git commit -m x'", "dot", "false", 2),
    ("git --config-env core.editor=EDITOR commit -m x", "dot", "false", 2),
    # commits that target another repo: not gated
    ("git commit -m x", "other", "false", 0),
    ("git -C {other} commit -m x", "dot", "false", 0),
    ("cd {other} && git commit -F msg.txt", "dot", "false", 0),
    ("git -C ~/other commit -m x", "dot", "false", 0),
    ("git -C $HOME/other commit -m x", "dot", "false", 0),
    ("git -C {other} add a.txt && git -C {other} commit -m x", "dot", "false", 0),
    ("bash -c 'git -C {other} commit -m x'", "dot", "false", 0),
    ("eval 'cd {other} && git commit -m x'", "dot", "false", 0),
    # target cannot be resolved: fail closed
    ("git -C {tmp}/missing commit -m x", "other", "false", 2),
    ("git -C {tmp} commit -m x", "other", "false", 2),
    ('git commit -m "unterminated', "other", "false", 2),
]


def git(*args: str, cwd: Path) -> None:
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=cwd, check=True, capture_output=True,
    )


class PrecommitGateHookTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._td = tempfile.TemporaryDirectory()
        cls.tmp = Path(os.path.realpath(cls._td.name))
        cls.dot = cls.tmp / "dotfiles"
        cls.other = cls.tmp / "other"
        cls.wt = cls.tmp / "dotfiles-wt"
        for repo in (cls.dot, cls.other):
            (repo / "scripts").mkdir(parents=True)
            git("init", "-q", cwd=repo)
            git("commit", "-q", "--allow-empty", "-m", "init", cwd=repo)
        cls.hook = cls.dot / "scripts" / HOOK.name
        shutil.copy2(HOOK, cls.hook)
        git("worktree", "add", "-q", str(cls.wt), cwd=cls.dot)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._td.cleanup()

    def run_hook(self, command: str, cwd: Path | None, gate: str,
                 extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
        payload = {"tool_name": "Bash", "tool_input": {"command": command}}
        if cwd is not None:
            payload["cwd"] = str(cwd)
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": str(self.tmp),
            "PRECOMMIT_GATE_CMD": gate,
            **(extra_env or {}),
        }
        runner = ["bash"] if self.hook.suffix == ".sh" else [sys.executable]
        return subprocess.run(
            [*runner, str(self.hook)], input=json.dumps(payload),
            capture_output=True, text=True, env=env, timeout=30,
        )

    def test_table(self) -> None:
        dirs = {"dot": self.dot, "other": self.other, "wt": self.wt}
        for template, cwd_key, gate, expected in CASES:
            command = template.format(dot=self.dot, other=self.other, wt=self.wt, tmp=self.tmp)
            with self.subTest(command=command, cwd=cwd_key, gate=gate):
                res = self.run_hook(command, dirs[cwd_key], gate)
                self.assertEqual(res.returncode, expected, res.stderr)
                if expected == 2:
                    self.assertIn("precommit-gate", res.stderr)

    def test_cwd_falls_back_to_project_dir(self) -> None:
        res = self.run_hook("git commit -m x", None, "false",
                            {"CLAUDE_PROJECT_DIR": str(self.other)})
        self.assertEqual(res.returncode, 0, res.stderr)
        res = self.run_hook("git commit -m x", None, "false",
                            {"CLAUDE_PROJECT_DIR": str(self.dot)})
        self.assertEqual(res.returncode, 2, res.stderr)

    def test_gate_runs_in_the_target_checkout(self) -> None:
        marker = self.tmp / "gate-cwd"
        gate = f'pwd -P > "{marker}"; false'
        res = self.run_hook(f"git -C {self.wt} commit -m x", self.other, gate)
        self.assertEqual(res.returncode, 2, res.stderr)
        self.assertEqual(marker.read_text().strip(), str(self.wt))

    def test_unresolved_target_says_so(self) -> None:
        res = self.run_hook(f"git -C {self.tmp}/missing commit -m x", self.other, "false")
        self.assertEqual(res.returncode, 2, res.stderr)
        self.assertIn("could not resolve", res.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
