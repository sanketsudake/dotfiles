#!/usr/bin/env python3
"""Usage/cost telemetry hook for Claude Code.

Turns transcripts into one JSON line per unit of work in
$CLAUDE_CONFIG_DIR/usage.jsonl, for measuring the routing table's savings
(rules/model-routing.md) and cache-hit ratio.

Events (wire all three; each is one settings.json entry):
  SubagentStop -> kind=subagent : the subagent's own transcript (agent_transcript_path; agent_type, model, tokens, duration)
  Stop         -> kind=turn     : the main transcript since the previous Stop (delta via a per-session offset)
  SessionEnd   -> kind=session  : totals for the whole main transcript, then the offset file is removed

Wired per-profile in settings.json (not tracked in this repo):
  {"hooks":{
    "SubagentStop":[{"matcher":"*","hooks":[{"type":"command","command":"python3 $CLAUDE_CONFIG_DIR/scripts/usage-log-hook.py","timeout":20}]}],
    "Stop":        [{"matcher":"*","hooks":[{"type":"command","command":"python3 $CLAUDE_CONFIG_DIR/scripts/usage-log-hook.py","timeout":20}]}],
    "SessionEnd":  [{"matcher":"*","hooks":[{"type":"command","command":"python3 $CLAUDE_CONFIG_DIR/scripts/usage-log-hook.py","timeout":20}]}]
  }}

Record shape (one line):
  {ts, kind, session_id, agent_id?, agent_type?, models:[..], turns, input, output,
   cache_read, cache_create, cache_hit, duration_s, transcript}
  cache_hit = cache_read / (input + cache_read + cache_create), 0..1

Never blocks: any failure exits 0 silently. Read the log with usage-report.py.
Stdlib only, Python 3.9+.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
LOG_FILE = CONFIG_DIR / "usage.jsonl"
STATE_DIR = CONFIG_DIR / "usage-state"


def parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def summarize(transcript: Path, start_line: int = 1) -> dict:
    """Sum assistant usage over transcript lines [start_line, EOF].

    Streaming rewrites the same requestId with growing usage, so the last record
    per requestId wins. The result also carries `lines`, the total line count of
    the file, so callers can advance a per-session offset without a second read.
    """
    latest: dict = {}  # request id -> {model, ts, usage}
    lineno = 0
    with transcript.open(encoding="utf-8", errors="replace") as fh:
        for lineno, line in enumerate(fh, start=1):
            if lineno < start_line or not line.strip():
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("type") != "assistant":
                continue
            msg = rec.get("message") or {}
            usage = msg.get("usage")
            if not usage:
                continue
            key = rec.get("requestId") or rec.get("uuid") or rec.get("timestamp")
            latest[key] = {"model": msg.get("model"), "ts": rec.get("timestamp"), "usage": usage}

    totals = {"turns": len(latest), "models": sorted({r["model"] for r in latest.values() if r["model"]}),
              "input": 0, "output": 0, "cache_read": 0, "cache_create": 0}
    stamps = []
    for r in latest.values():
        u = r["usage"]
        totals["input"] += u.get("input_tokens") or 0
        totals["output"] += u.get("output_tokens") or 0
        totals["cache_read"] += u.get("cache_read_input_tokens") or 0
        totals["cache_create"] += u.get("cache_creation_input_tokens") or 0
        if r["ts"]:
            stamps.append(r["ts"])
    context = totals["input"] + totals["cache_read"] + totals["cache_create"]
    totals["cache_hit"] = round(totals["cache_read"] / context, 3) if context else 0
    totals["duration_s"] = int((parse_ts(max(stamps)) - parse_ts(min(stamps))).total_seconds()) if stamps else 0
    totals["lines"] = lineno
    return totals


def emit(kind: str, session_id: str, transcript: Path, summary: dict, extra: dict) -> None:
    record = {"ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "kind": kind, "session_id": session_id}
    record.update(extra)
    record.update({k: v for k, v in summary.items() if k != "lines"})
    record["transcript"] = str(transcript)
    with LOG_FILE.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record) + "\n")


def handle(payload: dict) -> None:
    event = payload.get("hook_event_name") or ""
    transcript = Path(payload.get("transcript_path") or "")
    session_id = payload.get("session_id") or ""
    if not event or not transcript.is_file():
        return
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    if event == "SubagentStop":
        # transcript_path is the MAIN session's file; the subagent's own is agent_transcript_path.
        agent_transcript = Path(payload.get("agent_transcript_path") or "")
        if not agent_transcript.is_file():
            return
        summary = summarize(agent_transcript)
        if summary["turns"]:
            emit("subagent", session_id, agent_transcript, summary,
                 {"agent_id": payload.get("agent_id"), "agent_type": payload.get("agent_type")})

    elif event == "Stop":
        offset_file = STATE_DIR / session_id
        start = int(offset_file.read_text().strip() or 1) if offset_file.is_file() else 1
        summary = summarize(transcript, start)
        offset_file.write_text(str(summary["lines"] + 1))
        if summary["turns"]:
            emit("turn", session_id, transcript, summary, {})

    elif event == "SessionEnd":
        emit("session", session_id, transcript, summarize(transcript),
             {"reason": payload.get("reason") or payload.get("session_end_reason")})
        try:
            (STATE_DIR / session_id).unlink()
        except OSError:
            pass


def main() -> int:
    try:
        handle(json.load(sys.stdin))
    except Exception:  # noqa: BLE001 — telemetry must never block the session
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
