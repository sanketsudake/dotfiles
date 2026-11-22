#!/usr/bin/env python3
"""Custom status line script for Antigravity CLI.

Receives session state as JSON on stdin and prints a 2-line status bar:
  Line 1: [Model·Effort] 📁 folder | 🌿 branch [mode]
  Line 2: Context Bar [pct] | $cost | 👥 subagent | ⚙ task
"""
from __future__ import annotations

import json
import os
import subprocess
import sys


def main() -> None:
    try:
        raw = sys.stdin.read()
        if not raw:
            return
        data = json.loads(raw)
    except Exception:
        return

    # Model and effort tag
    model_obj = data.get("model") or {}
    model_raw = model_obj.get("display_name") or model_obj.get("id") or "Gemini"
    # Clean display name
    effort = model_obj.get("effort") or ""
    effort_tag = {
        "low": "L",
        "medium": "M",
        "high": "H",
        "xhigh": "XH",
        "max": "MAX",
    }.get(str(effort).lower(), "")

    model_tag = f"[{model_raw}·{effort_tag}]" if effort_tag else f"[{model_raw}]"

    # Directory and Workspace
    workspace = data.get("workspace") or {}
    cwd = workspace.get("current_dir") or data.get("cwd") or ""
    folder = os.path.basename(cwd) if cwd else ""

    # Git branch + dirty status
    branch = ""
    if cwd and os.path.isdir(cwd):
        try:
            res = subprocess.run(
                ["git", "-C", cwd, "symbolic-ref", "--quiet", "--short", "HEAD"],
                capture_output=True,
                text=True,
                timeout=1,
            )
            if res.returncode == 0 and res.stdout.strip():
                branch = res.stdout.strip()
            else:
                res_rev = subprocess.run(
                    ["git", "-C", cwd, "rev-parse", "--short", "HEAD"],
                    capture_output=True,
                    text=True,
                    timeout=1,
                )
                if res_rev.returncode == 0:
                    branch = res_rev.stdout.strip()
            if branch:
                status_res = subprocess.run(
                    ["git", "-C", cwd, "status", "--porcelain"],
                    capture_output=True,
                    text=True,
                    timeout=1,
                )
                if status_res.stdout.strip():
                    branch += "*"
        except Exception:
            pass

    # Execution mode (Shift+Tab cycle)
    mode = data.get("cycle_mode") or ""
    mode_str = f"[{mode}]" if mode else ""

    # Context window usage bar
    cw = data.get("context_window") or {}
    used_pct = cw.get("used_percentage")
    bar, pct_str = "", ""
    if used_pct is not None:
        used_val = float(used_pct)
        filled = min(20, max(0, int(used_val // 5)))
        bar = "█" * filled + "░" * (20 - filled)
        pct_str = f"{int(used_val)}%"

    # Cost
    cost_obj = data.get("cost") or {}
    total_cost = cost_obj.get("total_usd")
    cost_str = f"${total_cost:.2f}" if total_cost is not None and total_cost > 0 else ""

    # Subagents
    subagents = data.get("subagents") or []
    running_subs = [
        s for s in subagents if isinstance(s, dict) and s.get("status") == "running"
    ]
    subagent_str = (
        f"👥 {len(running_subs)} subagent{'s' if len(running_subs) > 1 else ''}"
        if running_subs
        else ""
    )

    # Background Tasks
    task_count = data.get("task_count") or 0
    task_str = f"⚙ {task_count} task{'s' if task_count > 1 else ''}" if task_count > 0 else ""

    # Line 1 formatting
    line1_parts = [f"\033[1;36m{model_tag}\033[0m"]
    if folder:
        line1_parts.append(f"\033[0;34m📁 {folder}\033[0m")
    if branch:
        line1_parts.append(f"\033[0;35m🌿 {branch}\033[0m")
    if mode_str:
        line1_parts.append(f"\033[0;33m{mode_str}\033[0m")
    line1 = " | ".join(line1_parts[:1] + [" ".join(line1_parts[1:])])

    # Line 2 formatting
    line2_items = []
    if bar:
        line2_items.append(f"\033[0;32m{bar}\033[0m \033[0;33m{pct_str}\033[0m")
    if cost_str:
        line2_items.append(f"\033[0;33m{cost_str}\033[0m")
    if subagent_str:
        line2_items.append(f"\033[0;35m{subagent_str}\033[0m")
    if task_str:
        line2_items.append(f"\033[0;36m{task_str}\033[0m")

    line2 = " | ".join(line2_items)

    print(line1)
    if line2:
        print(line2)


if __name__ == "__main__":
    main()
