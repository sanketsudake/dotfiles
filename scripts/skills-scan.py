#!/usr/bin/env python3
"""skills-scan.py — security-scan skills with NVIDIA SkillSpector
(https://github.com/NVIDIA/skillspector): prompt injection, exfiltration,
privilege escalation, supply chain, excessive agency, dangerous code, ...

Usage:
  skills-scan.py [--name NAME]... [--path DIR] [--llm] [--show-suppressed]
                 [--fail-at SCORE] [--report FILE] [--quiet] [--jobs N]

  default        scan every skill under skills/ (authored + materialized vendored)
  --name NAME    scan only skills/NAME (repeatable)
  --path DIR     scan an arbitrary skill directory (used by the fetch/update gate)
  --llm          add SkillSpector's LLM semantic pass via the local `claude` CLI
                 (SKILLSPECTOR_PROVIDER=claude_cli); default is static-only
  --fail-at N    fail when a skill's residual risk score is >= N (default 50)
  --report FILE  write the combined JSON report

Baselines (accepted findings, each with a reason) live in security/skillspector/:
_global.json applies to every skill, <name>.json to one. They are JSON in
SkillSpector's baseline schema (version 2, glob `rules`); global + per-skill are
merged into the baseline handed to the scanner.

Exit 1 when any skill fails: a residual HIGH/CRITICAL finding, or score >= --fail-at.
Exit 3 when skillspector is not installed:
  uv tool install git+https://github.com/NVIDIA/skillspector.git
Stdlib only, Python 3.9+.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO_ROOT / "skills"
BASELINE_DIR = REPO_ROOT / "security" / "skillspector"
INSTALL_HINT = "uv tool install git+https://github.com/NVIDIA/skillspector.git"
# Local build/cache artifacts: gitignored, never installed, but a scan of the
# live tree would flag them (a .pyc next to clean sources is a supply-chain hit).
EXPORT_IGNORE = shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store", "node_modules", ".venv", "bin")
FAIL_SEVERITIES = {"HIGH", "CRITICAL"}


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", action="append", default=[])
    ap.add_argument("--path")
    ap.add_argument("--llm", action="store_true")
    ap.add_argument("--show-suppressed", action="store_true")
    ap.add_argument("--fail-at", type=int, default=50)
    ap.add_argument("--report")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--jobs", type=int, default=int(os.environ.get("SKILLS_SCAN_JOBS", os.cpu_count() or 4)))
    return ap.parse_args()


def select_targets(args: argparse.Namespace) -> "list[tuple[str, Path]]":
    """(name, source dir) for every skill to scan."""
    if args.path:
        src = Path(args.path)
        if not (src / "SKILL.md").is_file():
            sys.exit(f"skills-scan: {src} has no SKILL.md")
        return [(src.name, src)]
    if args.name:
        out = []
        for name in args.name:
            src = SKILLS_DIR / name
            if not (src / "SKILL.md").is_file():
                sys.exit(f"skills-scan: skills/{name} has no SKILL.md (not materialized?)")
            out.append((name, src))
        return out
    return sorted((d.name, d) for d in SKILLS_DIR.iterdir() if (d / "SKILL.md").is_file())


def merged_baseline(name: str, tmp: Path) -> "Path | None":
    """Merge _global.json + <name>.json into one baseline file the scanner accepts."""
    parts = [p for p in (BASELINE_DIR / "_global.json", BASELINE_DIR / f"{name}.json") if p.is_file()]
    if not parts:
        return None
    merged = {"version": 2, "rules": [], "fingerprints": []}
    for p in parts:
        doc = json.loads(p.read_text())
        merged["rules"] += doc.get("rules", [])
        merged["fingerprints"] += doc.get("fingerprints", [])
    out = tmp / f"baseline-{name}.json"
    out.write_text(json.dumps(merged))
    return out


def scan_one(name: str, export: Path, tmp: Path, args: argparse.Namespace) -> dict:
    """Run one scanner process; a non-zero exit is its verdict, not an error,
    as long as the JSON report was written."""
    report = tmp / "reports" / f"{name}.json"
    cmd = ["skillspector", "scan", str(export), "--format", "json", "--output", str(report)]
    if not args.llm:
        cmd.append("--no-llm")
    baseline = merged_baseline(name, tmp)
    if baseline:
        cmd += ["--baseline", str(baseline)]
    if args.show_suppressed:
        cmd.append("--show-suppressed")
    env = dict(os.environ)
    if args.llm:
        env["SKILLSPECTOR_PROVIDER"] = "claude_cli"
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    try:
        doc = json.loads(report.read_text())
        assert "risk_assessment" in doc
    except (OSError, ValueError, AssertionError):
        return {"name": name, "error": (proc.stdout + proc.stderr)[-800:]}
    issues = doc.get("issues") or []
    return {
        "name": name,
        "doc": doc,
        "score": doc["risk_assessment"].get("score") or 0,
        "severity": doc["risk_assessment"].get("severity") or "?",
        "active": len(issues),
        "high": sum(1 for i in issues if i.get("severity") in FAIL_SEVERITIES),
        "suppressed": doc.get("suppressed_count") or 0,
    }


def describe(name: str, issue: dict) -> str:
    loc = issue.get("location") or {}
    where = str(loc.get("file"))
    if loc.get("start_line"):
        where += f":{loc['start_line']}"
    text = (issue.get("finding") or issue.get("explanation") or "").replace("\n", " ")[:140]
    return f"    {name}: [{issue.get('severity')}] {issue.get('id')} {issue.get('category')} @ {where} — {text}"


def main() -> int:
    args = parse_args()
    if not shutil.which("skillspector"):
        print(f"skills-scan: skillspector not installed — {INSTALL_HINT}", file=sys.stderr)
        return 3
    targets = select_targets(args)

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        (tmp / "reports").mkdir()
        exports = {}
        for name, src in targets:
            exports[name] = tmp / "skills" / name
            shutil.copytree(src, exports[name], ignore=EXPORT_IGNORE, symlinks=True)

        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            results = list(pool.map(lambda t: scan_one(t[0], exports[t[0]], tmp, args), targets))

        failed = False
        for r in results:
            if "error" in r:
                failed = True
                print(f"skills-scan: scanner error on {r['name']}:\n{r['error']}")
                continue
            r["status"] = "FAIL" if (r["high"] > 0 or r["score"] >= args.fail_at) else "ok"
            if r["status"] == "FAIL":
                failed = True
            if r["status"] == "FAIL" or (not args.quiet and r["active"]):
                for issue in r["doc"].get("issues") or []:
                    print(describe(r["name"], issue))
            if args.show_suppressed:
                for issue in r["doc"].get("suppressed") or []:
                    print(f"    {r['name']}: (suppressed) {issue.get('id')} {issue.get('category')} @ {(issue.get('location') or {}).get('file')}")

        print(f"{'status':<5} {'score':>5}  {'severity':<8} {'active':>6} {'high':>5} {'supp':>5}  skill")
        for r in sorted((r for r in results if "doc" in r), key=lambda r: -r["score"]):
            print(f"{r['status']:<5} {r['score']:>5}  {r['severity']:<8} {r['active']:>6} {r['high']:>5} {r['suppressed']:>5}  {r['name']}")

        if args.report:
            docs = [r["doc"] for r in results if "doc" in r]
            Path(args.report).write_text(json.dumps({"skill_count": len(docs), "skills": docs}, indent=1))
            print(f"report: {args.report}")

    if failed:
        rel = BASELINE_DIR.relative_to(REPO_ROOT)
        print(f"skills-scan: FAIL — a residual HIGH/CRITICAL finding or score >= {args.fail_at} "
              f"(fix it, or accept it with a reason in {rel}/<name>.json)", file=sys.stderr)
        return 1
    print(f"skills-scan: all {len(targets)} skill(s) pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
