#!/usr/bin/env python3
"""Regression test for the skills-scan export filter: the self-test scratch dir is excluded by exact location,
a directory of the same name anywhere else is exported (and therefore scanned)."""
import importlib.util
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("skills_scan", HERE / "skills-scan.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

fixture = mod.SKILLS_DIR / "polish-demo-recording" / "scripts" / "fixture"
fails = []
ignored = mod.export_ignore(str(fixture), [".work", "plan-v2.json", "__pycache__"])
if ignored != {".work", "__pycache__"}:
    fails.append(f"fixture dir: ignored {sorted(ignored)}, expected .work and __pycache__")
with tempfile.TemporaryDirectory() as tmp:
    other = Path(tmp) / "some-skill" / "scripts"
    other.mkdir(parents=True)
    (other / ".work").mkdir()
    ignored = mod.export_ignore(str(other), [".work", "run.py", "a.pyc"])
    if ignored != {"a.pyc"}:
        fails.append(f"other dir: ignored {sorted(ignored)}, expected only a.pyc (.work must be exported and scanned)")
if fails:
    print("\n".join("FAIL: " + f for f in fails))
    sys.exit(1)
print("skills-scan export filter: ok")
