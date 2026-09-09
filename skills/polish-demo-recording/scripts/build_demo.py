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

# ---------------------------------------------------------------- gaps (planning aid)
def load_words():
    d = json.load(open(PLAN['whisper']))
    return [(w['start'], w['end'], w['word'].strip()) for s in d['segments'] for w in s.get('words', [])]

def gaps():
    words = load_words()
    print(f'{"gap start":>9} {"gap end":>9} {"len":>5}  suggestion   next words')
    for i in range(1, len(words)):
        g = words[i][0] - words[i - 1][1]
        if g < 1.2: continue
        a, b = words[i - 1][1], words[i][0]
        sug = 'card?' if words[i][2][0].isupper() and g >= 1.2 else ''
        if g > 2.4: sug = (sug + ' speedup x' + ('4' if g > 4 else '3')).strip()
        nxt = ' '.join(w for _, _, w in words[i:i + 6])
        print(f'{a:9.2f} {b:9.2f} {g:5.1f}  {sug:12s} {nxt}')

VENC = F.venc(FPS)
AENC = F.AENC

# ---------------------------------------------------------------- overlays (ASS)
def ts(t):
    t = max(0.0, t); return f'{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}'
def ev(layer, a, b, style, text): return f'Dialogue: {layer},{ts(a)},{ts(b)},{style},,0,0,0,,{text}\n'
def rect(x1, y1, x2, y2, color, alpha='00'):
    return f'{{\\an7\\pos(0,0)\\p1\\1c&H{color}&\\1a&H{alpha}&\\bord0\\shad0}}m {x1} {y1} l {x2} {y1} {x2} {y2} {x1} {y2}{{\\p0}}'
def ass_header():
    return f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Hdr,Arial,30,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,4,0,0,0,1
Style: HdrMuted,Arial,26,&H00B8C0CC,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,6,0,0,0,1
Style: Box,Arial,20,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
Style: LT,Arial,34,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,4,0,0,0,1
Style: Badge,Arial,26,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,5,0,0,0,1
Style: Cap,Arial,40,&H00FFFFFF,&H00FFFFFF,&H00000000,&H90000000,0,0,0,0,100,100,0,0,3,10,0,2,60,60,42,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

def build_ass(tl, tm, captions=False):
    lines = [ass_header()]
    labels = sorted([(SRC_START, PLAN.get('first_label', 'Welcome'))] + [(c['cut'], c.get('label', c['title'])) for c in PLAN.get('chapters', [])] + [tuple(x) for x in PLAN.get('labels', [])])
    runs, cur = [], None
    for s in tl:
        if s['kind'] == 'src':
            if cur is None: cur = [s['out'], s['out'] + s['len'], s['a']]
            else: cur[1] = s['out'] + s['len']
        elif cur: runs.append(cur); cur = None
    if cur: runs.append(cur)
    if STRIP:
        for o1, o2, a in runs:
            lines.append(ev(2, o1, o2, 'Hdr', f'{{\\an4\\pos(40,{STRIP//2})\\1c&H{ACCENT_ASS}&}}{B["name"]}{{\\1c&HB8C0CC&\\fs26}}   {B.get("subtitle", "Product demo")}'))
            for i, (lt, lab) in enumerate(labels):
                nxt = labels[i + 1][0] if i + 1 < len(labels) else 1e9
                s1 = max(o1, tm.out_clamped(lt)); s2 = min(o2, tm.out_clamped(nxt) if nxt < 1e8 else o2)
                if lt <= a < nxt: s1 = o1
                if s2 - s1 > 0.2: lines.append(ev(2, s1, s2, 'HdrMuted', f'{{\\an6\\pos({W-40},{STRIP//2})}}' + lab))
    lt_y = (H - 280) if captions else (H - 116)
    callouts = PLAN.get('callouts', [])
    for i, (t, text) in enumerate(callouts):
        o1 = tm.out(t)
        if o1 is None: continue
        seg = tm.seg_of(t); nxt = callouts[i + 1][0] if i + 1 < len(callouts) else 1e9
        o2 = min(tm.out_clamped(min(t + CALLOUT_DUR, nxt - 0.3)), seg['out'] + seg['len'])
        w = tw(text, FR, 34) + 70; x1, y1 = 60, lt_y; x2, y2 = int(60 + w + 14), lt_y + 76; fad = '{\\fad(250,250)}'
        lines.append(ev(3, o1, o2, 'Box', fad + rect(x1, y1, x2, y2, '20120B', '30')))
        lines.append(ev(4, o1, o2, 'Box', fad + rect(x1, y1, x1 + 10, y2, ACCENT_ASS)))
        lines.append(ev(5, o1, o2, 'LT', fad + f'{{\\an4\\pos({x1+42},{y1+38})}}' + text))
    for s in tl:
        if s['kind'] == 'src' and s['badge']:
            o1, o2 = s['out'], s['out'] + s['len']; txt = f"{s['speed']}x  fast forward"
            w = tw(txt, FB, 26) + 44; x2, y2 = W - 60, H - 40; x1, y1 = int(x2 - w), y2 - 48
            lines.append(ev(3, o1, o2, 'Box', rect(x1, y1, x2, y2, '20120B', '30')))
            lines.append(ev(5, o1, o2, 'Badge', f'{{\\an5\\pos({(x1+x2)//2},{(y1+y2)//2})}}' + txt))
    if captions:
        for a, b, cl in load_captions():
            o1, o2 = tm.out(a), tm.out_clamped(b)
            if o1 is None: o1 = tm.out_clamped(a)
            if o2 - o1 > 0.3: lines.append(ev(6, o1, o2, 'Cap', '\\N'.join(cl)))
    return ''.join(lines)

def clean(text):
    for pat, rep in PLAN.get('caption_fixes', []) + [(r', uh,', ','), (r'\buh, ', ''), (r'\buh\b', ''), (r'  +', ' '), (r' ,', ',')]:
        text = re.sub(pat, rep, text)
    return text.strip()

def load_captions():
    """Cues from word timestamps: max 2 lines x 42 chars, break on pauses > 0.8 s, sentence ends, or 7 s."""
    words = load_words(); cues, cur = [], []
    def flush():
        if not cur: return
        text = clean(' '.join(w for _, _, w in cur))
        if len(text) < 3: cur.clear(); return
        lines, line = [], ''
        for tok in text.split():
            if line and len(line) + 1 + len(tok) > 42: lines.append(line); line = tok
            else: line = (line + ' ' + tok).strip()
        if line: lines.append(line)
        cues.append((cur[0][0], cur[-1][1], lines)); cur.clear()
    for a, b, w in words:
        if cur:
            gap = a - cur[-1][1]; length = len(' '.join(x for _, _, x in cur)) + 1 + len(w); ends = cur[-1][2].endswith(('.', '?', '!'))
            if gap > 0.8 or length > 84 or (ends and length > 40) or (b - cur[0][0]) > 7.0: flush()
        cur.append((a, b, w))
    flush()
    merged = []  # fold cues of fewer than three words into their neighbour so no caption is a lone word
    for a, b, lines in cues:
        words_n = sum(len(l.split()) for l in lines)
        if words_n < 3 and merged and a - merged[-1][1] < 2.5:
            pa, pb, pl = merged[-1]; text = ' '.join(pl) + ' ' + ' '.join(lines); nl, line = [], ''
            for tok in text.split():
                if line and len(line) + 1 + len(tok) > 42: nl.append(line); line = tok
                else: line = (line + ' ' + tok).strip()
            if line: nl.append(line)
            merged[-1] = (pa, b, nl)
        else: merged.append((a, b, lines))
    cues = []
    for a, b, lines in merged:
        if cues and sum(len(l.split()) for l in cues[-1][2]) < 3 and a - cues[-1][1] < 2.5:
            pa, pb, pl = cues.pop(); text = ' '.join(pl) + ' ' + ' '.join(lines); nl, line = [], ''
            for tok in text.split():
                if line and len(line) + 1 + len(tok) > 42: nl.append(line); line = tok
                else: line = (line + ' ' + tok).strip()
            if line: nl.append(line)
            cues.append((pa, b, nl))
        else: cues.append((a, b, lines))
    def wrap(text):
        nl, line = [], ''
        for tok in text.split():
            if line and len(line) + 1 + len(tok) > 42: nl.append(line); line = tok
            else: line = (line + ' ' + tok).strip()
        return nl + ([line] if line else [])
    def split(a, b, lines):
        """A cue longer than two lines is halved by word count (never by chopping a trailing line off)."""
        if len(lines) <= 2: return [(a, b, lines)]
        ws = ' '.join(lines).split(); h = len(ws) // 2; m = a + (b - a) * h / len(ws)
        return split(a, m, wrap(' '.join(ws[:h]))) + split(m, b, wrap(' '.join(ws[h:])))
    out = []
    for a, b, lines in cues: out += split(a, b, lines)
    return out

def write_srt(tm):
    n, lines = 0, []
    def st(t): h = int(t // 3600); m = int(t % 3600 // 60); s = t % 60; return f'{h:02d}:{m:02d}:{int(s):02d},{int((s % 1) * 1000):03d}'
    for a, b, cl in load_captions():
        o1, o2 = tm.out(a), tm.out_clamped(b)
        if o1 is None or o2 - o1 < 0.3: continue
        n += 1; lines.append(f'{n}\n{st(o1)} --> {st(o2)}\n' + '\n'.join(cl) + '\n\n')
    open(f'{OUT}.srt', 'w').write(''.join(lines))

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
