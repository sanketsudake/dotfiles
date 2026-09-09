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

VENC = F.venc(FPS)
AENC = F.AENC

# ---------------------------------------------------------------- verify
def verify(tl, tm):
    """Direct -ss seeks only: select=eq(n,..) contact sheets come out time-shifted on xfade output."""
    name = f'{OUT}.mp4'
    print(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type,duration,r_frame_rate', '-of', 'csv=p=0', name]).decode())
    out = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', name, '-af', 'ebur128=peak=true', '-f', 'null', '-'], capture_output=True, text=True).stderr
    print('\n'.join(l for l in out.splitlines() if re.match(r'^\s+(I|LRA|Peak):', l)))
    times = [(s['out'] + s['len'] / 2, os.path.basename(s['img'])) for s in tl if s['kind'] == 'card']
    times += [(tm.out(t) + 1.0, 'callout') for t, _ in PLAN.get('callouts', []) if tm.out(t) is not None]
    times += [(s['out'] + s['len'] / 2, 'badge') for s in tl if s['kind'] == 'src' and s['badge']]
    zooms = [s for s in tl if s['kind'] == 'src' and s['zoom']]
    times += [(s['out'] - XF / 2, 'dissolve') for s in tl if s['kind'] == 'card' and s['out'] > 0]
    times.sort(); os.makedirs('verify', exist_ok=True); files = []
    for i, (t, what) in enumerate(times):
        f = f'verify/{i:02d}.png'; files.append(f)
        ff('-ss', f'{t:.3f}', '-i', name, '-frames:v', '1', '-vf', f"scale=640:-1,drawtext=text='{t:.1f}s {what}':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f)
    # zooms are subtle by design (z <= 1.3): show the same region before (master) and after (final) at 1:1
    for i, s in enumerate(zooms):
        z, cx, cy = s['zoom']; mid_src = s['a'] + (s['b'] - s['a']) / 2; mid_out = s['out'] + s['len'] / 2
        cw, chh = 640, 360
        ff('-ss', f'{mid_src:.3f}', '-i', MASTER, '-frames:v', '1', '-vf', f"crop={cw}:{chh}:{max(0, min(cx - cw // 2, W - cw))}:{max(0, min(cy - chh // 2, H - chh))},drawtext=text='zoom {i+1} before, 1 to 1':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f'verify/z{i:02d}a.png')
        ff('-ss', f'{mid_out:.3f}', '-i', name, '-frames:v', '1', '-vf', f"crop={cw}:{chh}:{(W - cw) // 2}:{(H - chh) // 2},drawtext=text='zoom {i+1} after x{z}, 1 to 1':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f'verify/z{i:02d}b.png')
        files += [f'verify/z{i:02d}a.png', f'verify/z{i:02d}b.png']
    cols = 4; rows = (len(files) + cols - 1) // cols
    # simple, robust tiling: pad the list to a full grid then tile via concat of rows
    row_files = []
    for r in range(rows):
        chunk = files[r * cols:(r + 1) * cols]
        while len(chunk) < cols:
            if not os.path.exists('verify/blank.png'): ff('-f', 'lavfi', '-i', f'color=c=black:s=640x360', '-frames:v', '1', 'verify/blank.png')
            chunk.append('verify/blank.png')
        rf = f'verify/row{r}.png'; ff(*sum([['-i', f] for f in chunk], []), '-filter_complex', f'{"".join(f"[{i}]" for i in range(cols))}hstack=inputs={cols}', rf); row_files.append(rf)
    if len(row_files) == 1: os.replace(row_files[0], 'verify.png')
    else: ff(*sum([['-i', f] for f in row_files], []), '-filter_complex', f'{"".join(f"[{i}]" for i in range(len(row_files)))}vstack=inputs={len(row_files)}', 'verify.png')
    print(f'verify.png: {len(files)} frames (cards, callouts, badges, zooms, dissolves). Read it and check each one.')

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
