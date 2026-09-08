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
from PIL import Image, ImageDraw, ImageFont

if len(sys.argv) < 2: sys.exit(__doc__)
PLAN = json.load(open(sys.argv[1]))
STAGES = sys.argv[2:] or ['master', 'cards', 'segs', 'concat', 'ass', 'final']
WORK = os.path.abspath(PLAN.get('workdir', os.path.dirname(os.path.abspath(sys.argv[1])))); os.makedirs(WORK, exist_ok=True); os.chdir(WORK)
W, H = PLAN.get('width', 1920), PLAN.get('height', 1080)
STRIP = PLAN.get('chrome_top', 0)
STRIP_COLOR = PLAN.get('strip_color', '0b1220')
FPS = PLAN.get('fps', 30)
MASTER = 'master.mov'
B = PLAN.get('brand', {})
FB = B.get('font_bold', '/System/Library/Fonts/Supplemental/Arial Bold.ttf')
FR = B.get('font_regular', '/System/Library/Fonts/Supplemental/Arial.ttf')
def hexrgb(h): h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
ACCENT = hexrgb(B.get('accent', '#3b5bfd')); INK = hexrgb(B.get('ink', '#0b1220')); MUTED = hexrgb(B.get('muted', '#788296'))
BG = hexrgb(B.get('card_bg', '#f8fafc')); LIGHT = hexrgb(B.get('light', '#d5d9e2'))
ACCENT_ASS = '%02X%02X%02X' % (ACCENT[2], ACCENT[1], ACCENT[0])  # ASS colours are BGR
SRC_START, SRC_END = PLAN.get('src_start', 0.0), PLAN.get('src_end', 0.0)
CARD_DUR, OPEN_DUR, END_DUR = PLAN.get('card_dur', 2.4), PLAN.get('open_dur', 3.2), PLAN.get('end_dur', 5.0)
XF = PLAN.get('xfade', 0.45)
CALLOUT_DUR = PLAN.get('callout_dur', 5.0)
OUT = PLAN.get('out_prefix', 'final')

def run(cmd): subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
def ff(*args): run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *args])
def dur(path):
    return float(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=duration', '-of', 'default=nw=1:nk=1', path]).strip())
def font(p, s): return ImageFont.truetype(p, s)
def tw(text, p, s): return font(p, s).getlength(text)

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

# ---------------------------------------------------------------- master
def master():
    raw = PLAN['raw']; voice = PLAN['voice_wav']
    vf = f'fps={FPS}'
    if STRIP: vf += f',crop={W}:{H - STRIP}:0:{STRIP},pad={W}:{H}:0:{STRIP}:color=0x{STRIP_COLOR}'
    vf += ',format=yuv420p'
    ff('-i', raw, '-vf', vf, '-an', '-c:v', 'libx264', '-crf', '15', '-preset', 'fast', '-pix_fmt', 'yuv420p', 'master_v.mp4')
    ff('-i', 'master_v.mp4', '-i', voice, '-c:v', 'copy', '-c:a', 'pcm_s16le', '-shortest', MASTER)
    print('master.mov', dur(MASTER))

# ---------------------------------------------------------------- cards
def rounded(d, box, r, fill, outline=None): d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=2)

def make_cards():
    os.makedirs('cards', exist_ok=True)
    for i, c in enumerate(PLAN.get('chapters', []), 1):
        im = Image.new('RGB', (W, H), BG); d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 16, H], fill=ACCENT)
        d.text((150, 110), B['name'], font=font(FB, 52), fill=ACCENT)
        d.text((156, 330), 'CHAPTER', font=font(FR, 40), fill=MUTED)
        d.text((150, 360), f'{i:02d}', font=font(FB, 200), fill=LIGHT)
        d.text((156, 620), c['title'], font=font(FB, 96), fill=INK)
        d.rectangle([160, 770, 600, 780], fill=ACCENT)
        if c.get('subtitle'): d.text((160, 815), c['subtitle'], font=font(FR, 40), fill=MUTED)
        im.save(f'cards/ch{i}.png')
    im = Image.new('RGB', (W, H), BG); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 16, H], fill=ACCENT)
    d.text((150, 110), B.get('subtitle', 'Product demo'), font=font(FR, 40), fill=MUTED)
    d.text((146, 300), B['name'], font=font(FB, 180), fill=ACCENT)
    if B.get('tagline'): d.text((156, 520), B['tagline'], font=font(FB, 58), fill=INK)
    if B.get('blurb'): d.text((158, 605), B['blurb'], font=font(FR, 36), fill=MUTED)
    tiles = B.get('tiles', [])
    if tiles:
        x, y, th, gap = 160, 760, 150, 22; tw_ = int((W - 320 - gap * (len(tiles) - 1)) / len(tiles))
        for t, s in tiles:
            rounded(d, [x, y, x + tw_, y + th], 18, (255, 255, 255), outline=(226, 230, 238))
            d.rectangle([x, y, x + 6, y + th], fill=ACCENT)
            d.text((x + 28, y + 36), t, font=font(FB, 30), fill=INK)
            d.text((x + 28, y + 84), s, font=font(FR, 24), fill=MUTED)
            x += tw_ + gap
    if B.get('footer'): d.text((160, 980), B['footer'], font=font(FB, 34), fill=INK)
    im.save('cards/open.png')
    im = Image.new('RGB', (W, H), BG); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 16, H], fill=ACCENT)
    d.text((150, 110), B['name'], font=font(FB, 52), fill=ACCENT)
    d.text((150, 360), B.get('end_title', 'Thank you'), font=font(FB, 150), fill=INK)
    d.rectangle([160, 560, 600, 570], fill=ACCENT)
    for k, line in enumerate(B.get('end_lines', [])): d.text((160, 610 + 55 * k), line, font=font(FR, 40), fill=MUTED)
    if B.get('footer'): d.text((160, 980), B['footer'], font=font(FB, 34), fill=INK)
    im.save('cards/end.png')

# ---------------------------------------------------------------- timeline
def build_timeline():
    assert B.get('name') and SRC_END > SRC_START, 'plan.json needs brand.name, src_start and src_end'
    ops = []
    for i, c in enumerate(PLAN.get('chapters', []), 1): ops.append((c['cut'], c.get('resume', c['cut']), 'card', i))
    for a, b, s, badge in PLAN.get('speedups', []): ops.append((a + 0.5, b - 0.4, 'speed', (s, badge)))
    for a, b, z, cx, cy in PLAN.get('zooms', []): ops.append((a, b, 'zoom', (z, cx, cy)))
    ops.sort()
    for i in range(1, len(ops)): assert ops[i][0] >= ops[i - 1][1], f'overlapping ops: {ops[i-1]} {ops[i]}'
    tl = [dict(kind='card', img='cards/open.png', dur=OPEN_DUR)]
    cur = SRC_START
    def src(a, b, speed=1, badge=False, zoom=None):
        if b - a > 0.05: tl.append(dict(kind='src', a=a, b=b, speed=speed, badge=badge, zoom=zoom))
    for a, b, kind, p in ops:
        src(cur, a)
        if kind == 'card': tl.append(dict(kind='card', img=f'cards/ch{p}.png', dur=CARD_DUR, chapter=p)); cur = b
        elif kind == 'speed': src(a, b, speed=p[0], badge=p[1]); cur = b
        else: src(a, b, zoom=p); cur = b
    end = min(SRC_END, dur(MASTER) - 0.05)
    if end < SRC_END: print(f'warning: src_end {SRC_END} is past the master ({dur(MASTER):.2f}s); clamped to {end:.2f}')
    for a, b, kind, p in ops: assert b <= end, f'op {kind} {a}-{b} lies past the end of the master ({end:.2f}s)'
    src(cur, end)
    tl.append(dict(kind='card', img='cards/end.png', dur=END_DUR))
    return tl

VENC = ['-r', str(FPS), '-c:v', 'libx264', '-crf', '16', '-preset', 'medium', '-pix_fmt', 'yuv420p', '-video_track_timescale', '30000']
AENC = ['-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2']

def zoom_vf(z, cx, cy, D):
    """Eased push-in (smoothstep, 0.7 s in/out) on the content area only; the strip is cropped off and padded back."""
    e = f'min(1,max(0,min(t/0.7,({D:.3f}-t)/0.7)))'; E = f'(({e})*({e})*(3-2*({e})))'; Z = f'(1+{z-1:.3f}*{E})'
    ch = H - STRIP; cyc = cy - STRIP
    return (f'crop={W}:{ch}:0:{STRIP},'
            f"scale=w='trunc({W}*{Z}/2)*2':h='trunc({ch}*{Z}/2)*2':eval=frame,"
            f"crop={W}:{ch}:x='min(max({cx}*{Z}-{W/2},0),iw-{W})':y='min(max({cyc}*{Z}-{ch/2},0),ih-{ch})',"
            f'pad={W}:{H}:0:{STRIP}:color=0x{STRIP_COLOR}')

def build_pieces(tl):
    pieces = []
    for s in tl:
        if s['kind'] == 'card': pieces.append(('card', [s]))
        elif pieces and pieces[-1][0] == 'run': pieces[-1][1].append(s)
        else: pieces.append(('run', [s]))
    return pieces

def render_segs(tl):
    os.makedirs('seg', exist_ok=True)
    for i, s in enumerate(tl):
        out = f'seg/{i:03d}.mp4'; s['file'] = out
        if os.path.exists(out) and 'segs' not in STAGES: continue
        if s['kind'] == 'card':
            ff('-loop', '1', '-framerate', str(FPS), '-t', str(s['dur']), '-i', s['img'], '-f', 'lavfi', '-t', str(s['dur']), '-i', 'anullsrc=r=48000:cl=stereo',
               '-vf', f'scale={W}:{H},format=yuv420p', '-t', str(s['dur']), *VENC, *AENC, out)
        else:
            D = s['b'] - s['a']; vf = f'fps={FPS}'; af = 'anull'
            if s['speed'] != 1: vf = f"setpts=PTS/{s['speed']},fps={FPS}"; af = f"atempo={s['speed']},volume=0"
            if s['zoom']: vf = f'fps={FPS},' + zoom_vf(*s['zoom'], D)
            ff('-ss', f"{s['a']:.3f}", '-t', f'{D:.3f}', '-i', MASTER, '-vf', vf, '-af', af, *VENC, *AENC, out)
        print(f"{out} {s['kind']} {s.get('a','')}-{s.get('b','')} x{s.get('speed','')}", flush=True)
    for s in tl:
        s['len'] = dur(s['file'])
        assert s['len'] > 0, f"segment {s['file']} is empty: {s}"
    chain = 0.0
    for k, (kind, segs) in enumerate(build_pieces(tl)):
        t = chain - (XF if k > 0 else 0.0)
        for s in segs: s['out'] = t; t += s['len']
        chain = t
    return chain

def concat(tl):
    files = []
    for k, (kind, segs) in enumerate(build_pieces(tl)):
        if kind == 'card': files.append(segs[0]['file']); continue
        lst, out = f'seg/run{k:02d}.txt', f'seg/run{k:02d}.mp4'
        with open(lst, 'w') as f:
            for s in segs: f.write(f"file '{os.path.abspath(s['file'])}'\n")
        ff('-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', out); files.append(out)
    lens = [dur(f) for f in files]; inputs = []; fc = []; chain = lens[0]; v, a = '[0:v]', '[0:a]'
    for f in files: inputs += ['-i', f]
    for i in range(1, len(files)):
        off = chain - XF
        fc.append(f'{v}[{i}:v]xfade=transition=fade:duration={XF}:offset={off:.3f}[v{i}]')
        fc.append(f'{a}[{i}:a]acrossfade=d={XF}:c1=tri:c2=tri[a{i}]')
        v, a = f'[v{i}]', f'[a{i}]'; chain = off + lens[i]
    fc.append(f'{v}fade=t=in:d=0.6,fade=t=out:st={chain-0.8:.3f}:d=0.8,format=yuv420p[vout]'); fc.append(f'{a}anull[aout]')
    ff(*inputs, '-filter_complex', ';'.join(fc), '-map', '[vout]', '-map', '[aout]', *VENC, *AENC, '-movflags', '+faststart', 'cut.mp4')
    print(f'cut.mp4 expected {chain:.2f}s, actual {dur("cut.mp4"):.2f}s')

# ---------------------------------------------------------------- time map
class TimeMap:
    def __init__(self, tl): self.tl = tl
    def seg_of(self, t):
        for s in self.tl:
            if s['kind'] == 'src' and s['a'] <= t < s['b']: return s
    def out(self, t):
        s = self.seg_of(t); return None if s is None else s['out'] + (t - s['a']) / s['speed']
    def out_clamped(self, t):
        best = 0.0
        for s in self.tl:
            if s['kind'] != 'src': continue
            if s['a'] <= t < s['b']: return s['out'] + (t - s['a']) / s['speed']
            if s['b'] <= t: best = s['out'] + s['len']
        return best

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

# ---------------------------------------------------------------- final mix
def final(name, ass, music):
    T = dur('cut.mp4'); inputs = ['-i', 'cut.mp4']
    if music:
        inputs += ['-stream_loop', '-1', '-i', music['path']]
        fc = (f"[1:a]volume={music.get('volume', 0.17)},atrim=0:{T:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=2,afade=t=out:st={T-4.5:.3f}:d=4.5[m0];"
              f"[0:a]asplit[v1][v2];[m0][v2]sidechaincompress=threshold=0.015:ratio=8:attack=30:release=600:makeup=1[md];"
              f"[v1][md]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.89:level=false[a];")
    else: fc = '[0:a]anull[a];'
    fc += f'[0:v]ass={ass}[v]'
    ff(*inputs, '-filter_complex', fc, '-map', '[v]', '-map', '[a]', '-t', f'{T:.3f}',
       '-c:v', 'libx264', '-crf', '18', '-preset', 'slow', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
       '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', name)
    print('wrote', name, dur(name), flush=True)

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
