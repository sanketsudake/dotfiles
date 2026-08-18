#!/usr/bin/env python3
"""skills-scan.py — security-scan skills with NVIDIA SkillSpector
(https://github.com/NVIDIA/skillspector): prompt injection, exfiltration,
privilege escalation, supply chain, excessive agency, dangerous code, ...

Usage:
  skills-scan.py [--name NAME]... [--path DIR] [--llm] [--show-suppressed]
                 [--fail-at SCORE] [--report FILE] [--quiet] [--jobs N]

  default        scan every skill under skills/ (authored + materialized vendored)
  --name NAME    scan only skills/NAME (repeatable)
  --path DIR     scan an arbitrary skill directory (used by the fetch/update gate);
                 with --name NAME the baseline lookup uses NAME instead of DIR's basename
  --llm          add SkillSpector's LLM semantic pass via the local `claude` CLI
                 (SKILLSPECTOR_PROVIDER=claude_cli); default is static-only
  --fail-at N    fail when a skill's residual risk score is >= N (default 50)
  --report FILE  write the combined JSON report

Baselines (accepted findings, each with a reason) live in security/skillspector/:
_global.json applies to every skill, <name>.json to one. They are JSON in
SkillSpector's baseline schema (version 2, glob `rules`); global + per-skill are
merged into the baseline handed to the scanner.

Exit 1 when any skill fails: a residual HIGH/CRITICAL finding, or score >= --fail-at.
Exit 3 when skillspector is not installed: `make skillspector-install`
(pinned to SKILLSPECTOR_REF in the Makefile).
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
INSTALL_HINT = "make skillspector-install (pinned to SKILLSPECTOR_REF in the Makefile)"
# Local build/cache artifacts: gitignored, never installed, but a scan of the
# live tree would flag them (a .pyc next to clean sources is a supply-chain hit).
EXPORT_IGNORE = shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store", "node_modules", ".venv")
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


def select_targets(args: argparse.Namespace) -> list[tuple[str, Path]]:
    """(name, source dir) for every skill to scan."""
    if args.path:
        src = Path(args.path)
        if not (src / "SKILL.md").is_file():
            sys.exit(f"skills-scan: {src} has no SKILL.md")
        return [(args.name[0] if args.name else src.name, src)]
    if args.name:
        out = []
        for name in args.name:
            src = SKILLS_DIR / name
            if not (src / "SKILL.md").is_file():
                sys.exit(f"skills-scan: skills/{name} has no SKILL.md (not materialized?)")
            out.append((name, src))
        return out
    return sorted((d.name, d) for d in SKILLS_DIR.iterdir() if (d / "SKILL.md").is_file())


def load_baseline(path: Path) -> dict:
    """{"rules": [...], "fingerprints": [...]} from a baseline file, or empty."""
    if not path.is_file():
        return {"rules": [], "fingerprints": []}
    doc = json.loads(path.read_text())
    return {"rules": doc.get("rules", []), "fingerprints": doc.get("fingerprints", [])}


def merged_baseline(name: str, global_rules: dict, tmp: Path) -> Path | None:
    """Merge the global rules + <name>.json into one baseline file the scanner accepts."""
    own = load_baseline(BASELINE_DIR / f"{name}.json")
    if not (global_rules["rules"] or global_rules["fingerprints"] or own["rules"] or own["fingerprints"]):
        return None
    out = tmp / f"baseline-{name}.json"
    out.write_text(json.dumps({"version": 2,
                               "rules": global_rules["rules"] + own["rules"],
                               "fingerprints": global_rules["fingerprints"] + own["fingerprints"]}))
    return out


def scan_one(name: str, export: Path, global_rules: dict, tmp: Path, args: argparse.Namespace) -> dict:
    """Run one scanner process and classify its report.

    Returns {"name", "status": "ok"|"FAIL"|"error", ...}. A non-zero scanner exit
    is its verdict, not an error, as long as a well-formed JSON report was written.
    """
    report = tmp / "reports" / f"{name}.json"
    cmd = ["skillspector", "scan", str(export), "--format", "json", "--output", str(report)]
    if not args.llm:
        cmd.append("--no-llm")
    baseline = merged_baseline(name, global_rules, tmp)
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
        if "risk_assessment" not in doc or "issues" not in doc:
            raise ValueError("report is missing risk_assessment/issues")
    except (OSError, ValueError) as exc:
        return {"name": name, "status": "error", "error": f"{exc}\n{(proc.stdout + proc.stderr)[-800:]}"}
    issues = doc["issues"] or []
    score = doc["risk_assessment"].get("score") or 0
    high = sum(1 for i in issues if i.get("severity") in FAIL_SEVERITIES)
    return {
        "name": name,
        "status": "FAIL" if (high > 0 or score >= args.fail_at) else "ok",
        "doc": doc,
        "score": score,
        "severity": doc["risk_assessment"].get("severity") or "?",
        "active": len(issues),
        "high": high,
        "suppressed": doc.get("suppressed_count") or 0,
    }


def describe(name: str, issue: dict) -> str:
    loc = issue.get("location") or {}
    where = str(loc.get("file") or "?")
    if loc.get("start_line"):
        where += f":{loc['start_line']}"
    text = (issue.get("finding") or issue.get("explanation") or "").replace("\n", " ")[:140]
    return f"    {name}: [{issue.get('severity')}] {issue.get('id')} {issue.get('category')} @ {where} — {text}"


def print_findings(results: list, args: argparse.Namespace) -> None:
    """Per-finding lines: every finding of a failing skill; of passing skills only unless --quiet."""
    for r in results:
        if r["status"] == "error":
            print(f"skills-scan: scanner error on {r['name']}:\n{r['error']}")
            continue
        if r["status"] == "FAIL" or (not args.quiet and r["active"]):
            for issue in r["doc"]["issues"] or []:
                print(describe(r["name"], issue))
        if args.show_suppressed:
            for issue in r["doc"].get("suppressed") or []:
                loc = issue.get("location") or {}
                print(f"    {r['name']}: (suppressed) {issue.get('id')} {issue.get('category')} @ {loc.get('file')}")


def print_summary(results: list) -> None:
    print(f"{'status':<5} {'score':>5}  {'severity':<8} {'active':>6} {'high':>5} {'supp':>5}  skill")
    for r in sorted((r for r in results if r["status"] != "error"), key=lambda r: -r["score"]):
        print(f"{r['status']:<5} {r['score']:>5}  {r['severity']:<8} {r['active']:>6} {r['high']:>5} {r['suppressed']:>5}  {r['name']}")


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

        global_rules = load_baseline(BASELINE_DIR / "_global.json")
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            results = list(pool.map(lambda t: scan_one(t[0], exports[t[0]], global_rules, tmp, args), targets))

        print_findings(results, args)
        print_summary(results)
        if args.report:
            docs = [r["doc"] for r in results if r["status"] != "error"]
            Path(args.report).write_text(json.dumps({"skill_count": len(docs), "skills": docs}, indent=1))
            print(f"report: {args.report}")
        failed = any(r["status"] != "ok" for r in results)

    if failed:
        rel = BASELINE_DIR.relative_to(REPO_ROOT)
        print(f"skills-scan: FAIL — a residual HIGH/CRITICAL finding or score >= {args.fail_at} "
              f"(fix it, or accept it with a reason in {rel}/<name>.json)", file=sys.stderr)
        return 1
    print(f"skills-scan: all {len(targets)} skill(s) pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
