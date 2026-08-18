#!/usr/bin/env python3
"""Aggregate $CLAUDE_CONFIG_DIR/usage.jsonl (written by usage-log-hook.py).

  1. subagent spend by agent_type x model — is the routing table saving anything?
  2. per-day main-session turns with cache-hit ratio — a dip right after a
     CLAUDE.md / rules / skills change is the cache prefix being invalidated.

Usage: usage-report.py [--since DAYS] [--log FILE]...
  default: last 30 days, the current profile's log. `make usage-report` runs it
  for every profile.
Stdlib only, Python 3.9+.
"""
from __future__ import annotations

import argparse
import json
import os
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path


def fmt(n: float) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(int(n))


def pct(x: float) -> str:
    return f"{round(x * 100)}%"


def context_tokens(rec: dict) -> int:
    return rec.get("cache_read", 0) + rec.get("input", 0) + rec.get("cache_create", 0)


def agg(records: list) -> "tuple[int, int, float]":
    """(output tokens, context tokens, cache-hit ratio) over a group of records."""
    out = sum(r.get("output", 0) for r in records)
    ctx = sum(context_tokens(r) for r in records)
    hit = sum(r.get("cache_read", 0) for r in records) / ctx if ctx else 0
    return out, ctx, hit


def load(log: Path, cutoff: str) -> list:
    records = []
    with log.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("ts", "") >= cutoff:
                records.append(rec)
    return records


def report(log: Path, cutoff: str) -> None:
    print(f"== {log} (since {cutoff})")
    if not log.is_file() or log.stat().st_size == 0:
        print("   (no records)")
        return
    records = load(log, cutoff)
    subagents = [r for r in records if r.get("kind") == "subagent"]
    turns = [r for r in records if r.get("kind") == "turn"]

    # 1. subagents by agent_type x model
    groups: dict = defaultdict(list)
    for r in subagents:
        groups[(r.get("agent_type") or "?", "+".join(r.get("models") or []) or "?")].append(r)
    print(f"-- subagents by agent_type x model ({len(subagents)} runs)")
    print(f"   {'runs':>4}  {'out-tok':>8}  {'ctx-tok':>8}  {'cache':>5}  {'avg-s':>5}  agent_type / model")
    rows = []
    for (agent_type, model), rs in groups.items():
        out, ctx, hit = agg(rs)
        avg = sum(r.get("duration_s", 0) for r in rs) / len(rs)
        rows.append((out, len(rs), ctx, hit, avg, f"{agent_type} / {model}"))
    for out, n, ctx, hit, avg, key in sorted(rows, reverse=True):
        print(f"   {n:>4}  {fmt(out):>8}  {fmt(ctx):>8}  {pct(hit):>5}  {round(avg):>5}  {key}")

    # 2. main-session turns per day
    days: dict = defaultdict(list)
    for r in turns:
        days[r.get("ts", "")[:10]].append(r)
    print()
    print(f"-- main-session turns per day ({len(turns)} turns)")
    print(f"   {'day':<10}  {'turns':>5}  {'out-tok':>8}  {'ctx-tok':>8}  {'cache':>5}")
    for day in sorted(days):
        rs = days[day]
        n = sum(r.get("turns", 0) for r in rs)
        out, ctx, hit = agg(rs)
        print(f"   {day:<10}  {n:>5}  {fmt(out):>8}  {fmt(ctx):>8}  {pct(hit):>5}")
    print()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", type=int, default=30, help="days back (default 30)")
    ap.add_argument("--log", action="append", type=Path, help="usage.jsonl to read (repeatable)")
    args = ap.parse_args()
    logs = args.log or [Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / "usage.jsonl"]
    cutoff = (datetime.now(timezone.utc) - timedelta(days=args.since)).strftime("%Y-%m-%dT%H:%M:%SZ")
    for log in logs:
        report(log, cutoff)


if __name__ == "__main__":
    main()
