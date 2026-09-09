#!/usr/bin/env python3
"""Build a polished demo video from a JSON edit plan. Run with: uv run --with "pillow>=10" build_demo.py <plan.json> [stages...]

Stages (default: all): master cards segs concat ass final verify gaps
  gaps   - print the narration gaps from the whisper JSON with a suggested treatment (card / speedup), then exit
  master - crop the browser chrome, pad a branded strip back, constant fps; mux the processed voice WAV
  cards  - render title, chapter and end cards (Pillow)
  segs   - cut every timeline segment from the master (speed-ups, eased zooms) with identical encode settings
  concat - join runs with -c copy, then one xfade/acrossfade chain across every card boundary
  ass    - lower-thirds, header labels, fast-forward badges, optional captions, .srt sidecar (time-mapped)
  final  - overlays + optional sidechain-ducked music, three variants (music / no music / captions)
  verify - stream durations, loudness, and verify.png: direct-seek frames at every card, callout, badge and zoom
The stages live in ./demo/ (plan, timeline, render, overlays, verify, cli).
See ../references/ffmpeg-recipes.md for why each parameter is what it is.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from demo.cli import main  # noqa: E402

if __name__ == '__main__':
    sys.exit(main())
