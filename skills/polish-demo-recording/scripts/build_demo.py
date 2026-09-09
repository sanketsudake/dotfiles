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
See ../references/ffmpeg-recipes.md for why each parameter is what it is.
"""
import json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFont
from demo import ffmpeg as F
from demo import plan as P

if len(sys.argv) < 2: sys.exit(__doc__)
ctx = P.load(sys.argv[1])
STAGES = sys.argv[2:] or ['master', 'cards', 'segs', 'concat', 'ass', 'final']
PLAN = ctx.plan
W, H, STRIP, STRIP_COLOR, FPS, MASTER = ctx.W, ctx.H, ctx.strip, ctx.strip_color, ctx.fps, ctx.master
B, FB, FR = ctx.brand, ctx.fb, ctx.fr
ACCENT, INK, MUTED, BG, LIGHT, ACCENT_ASS = ctx.accent, ctx.ink, ctx.muted, ctx.bg, ctx.light, ctx.accent_ass
SRC_START, SRC_END = ctx.src_start, ctx.src_end
CARD_DUR, OPEN_DUR, END_DUR, XF, CALLOUT_DUR, OUT = ctx.card_dur, ctx.open_dur, ctx.end_dur, ctx.xf, ctx.callout_dur, ctx.out
hexrgb = P.hexrgb
run, ff, dur = F.run, F.ff, F.dur
from demo import render as R
font, tw = R.font, R.tw
def master(): R.master(ctx)
def make_cards(): R.make_cards(ctx)
def zoom_vf(z, cx, cy, D): return R.zoom_vf(ctx, z, cx, cy, D)
from demo import timeline as T
def build_timeline(): return T.build_timeline(ctx)
build_pieces, TimeMap = T.build_pieces, T.TimeMap
def render_segs(tl): return R.render_segs(ctx, tl, 'segs' in STAGES)
def concat(tl): R.concat(ctx, tl)
def final(name, ass, music): R.final(ctx, name, ass, music)
from demo import overlays as O
def load_words(): return O.load_words(ctx)
def gaps(): O.gaps(ctx)
def build_ass(tl, tm, captions=False): return O.build_ass(ctx, tl, tm, captions)
def write_srt(tm): O.write_srt(ctx, tm)
from demo import verify as V
def verify(tl, tm): V.verify(ctx, tl, tm)

VENC = F.venc(FPS)
AENC = F.AENC

if __name__ == '__main__':
    if 'gaps' in STAGES: gaps(); sys.exit(0)
    if 'master' in STAGES: master()
    if 'cards' in STAGES: make_cards(); print('cards ok')
    tl = build_timeline(); total = render_segs(tl); print(f'timeline: {len(tl)} segments, {total:.1f}s (with dissolves)')
    json.dump(tl, open('timeline.json', 'w'), indent=1)
    if 'concat' in STAGES: concat(tl)
    tm = TimeMap(tl)
    if 'ass' in STAGES:
        open('overlays.ass', 'w').write(build_ass(tl, tm)); open('overlays_cc.ass', 'w').write(build_ass(tl, tm, captions=True)); write_srt(tm); print('overlays + srt ok')
    if 'final' in STAGES:
        music = PLAN.get('music')
        if music: final(f'{OUT}.mp4', 'overlays.ass', music); final(f'{OUT}-captions.mp4', 'overlays_cc.ass', music); final(f'{OUT}-no-music.mp4', 'overlays.ass', None)
        else: final(f'{OUT}.mp4', 'overlays.ass', None); final(f'{OUT}-captions.mp4', 'overlays_cc.ass', None)
    if 'verify' in STAGES: verify(tl, tm)
