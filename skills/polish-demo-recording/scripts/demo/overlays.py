"""Overlays as one ASS file (header strip, chapter labels, lower-third callouts, fast-forward badges,
captions), the .srt sidecar, and the gap report used for planning. All times are mapped through TimeMap."""
import json
import re
from demo.render import fs, sx, sy, tw


def load_words(ctx):
    d = json.load(open(ctx.transcript))
    return [(w['start'], w['end'], w['word'].strip()) for s in d['segments'] for w in s.get('words', [])]


def gaps(ctx):
    """Print every narration gap of 1.2 s or more with a suggested treatment (card, speed-up)."""
    words = load_words(ctx)
    print(f'{"gap start":>9} {"gap end":>9} {"len":>5}  suggestion   next words')
    for i in range(1, len(words)):
        g = words[i][0] - words[i - 1][1]
        if g < 1.2:
            continue
        a, b = words[i - 1][1], words[i][0]
        sug = 'card?' if words[i][2][0].isupper() and g >= 1.2 else ''
        if g > 2.4:
            sug = (sug + ' speedup x' + ('4' if g > 4 else '3')).strip()
        nxt = ' '.join(w for _, _, w in words[i:i + 6])
        print(f'{a:9.2f} {b:9.2f} {g:5.1f}  {sug:12s} {nxt}')


def ts(t):
    t = max(0.0, t)
    return f'{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}'


def ev(layer, a, b, style, text):
    return f'Dialogue: {layer},{ts(a)},{ts(b)},{style},,0,0,0,,{text}\n'


def rect(x1, y1, x2, y2, color, alpha='00'):
    return f'{{\\an7\\pos(0,0)\\p1\\1c&H{color}&\\1a&H{alpha}&\\bord0\\shad0}}m {x1} {y1} l {x2} {y1} {x2} {y2} {x1} {y2}{{\\p0}}'


def ass_header(ctx):
    return f"""[Script Info]
ScriptType: v4.00+
PlayResX: {ctx.W}
PlayResY: {ctx.H}
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Hdr,{ctx.font_family},{fs(ctx, 30)},&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,4,0,0,0,1
Style: HdrMuted,{ctx.font_family},{fs(ctx, 26)},&H00B8C0CC,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,6,0,0,0,1
Style: Box,{ctx.font_family},{fs(ctx, 20)},&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
Style: LT,{ctx.font_family},{fs(ctx, 34)},&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,4,0,0,0,1
Style: Badge,{ctx.font_family},{fs(ctx, 26)},&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,5,0,0,0,1
Style: Cap,{ctx.font_family},{fs(ctx, 40)},&H00FFFFFF,&H00FFFFFF,&H00000000,&H90000000,0,0,0,0,100,100,0,0,3,{sy(ctx, 10)},0,2,{sx(ctx, 60)},{sx(ctx, 60)},{sy(ctx, 42)},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def build_ass(ctx, tl, tm, captions=False):
    lines = [ass_header(ctx)]
    labels = sorted([(ctx.src_start, ctx.first_label)] + [(c['cut'], c.get('label', c['title'])) for c in ctx.chapters] + list(ctx.labels))
    runs, cur = [], None
    for s in tl:
        if s['kind'] == 'src':
            if cur is None:
                cur = [s['out'], s['out'] + s['len'], s['a']]
            else:
                cur[1] = s['out'] + s['len']
        elif cur:
            runs.append(cur)
            cur = None
    if cur:
        runs.append(cur)
    if ctx.strip:
        for o1, o2, a in runs:
            lines.append(ev(2, o1, o2, 'Hdr', f'{{\\an4\\pos({sx(ctx, 40)},{ctx.strip//2})\\1c&H{ctx.accent_ass}&}}{ctx.brand["name"]}{{\\1c&HB8C0CC&\\fs{fs(ctx, 26)}}}   {ctx.brand.get("subtitle", "Product demo")}'))
            for i, (lt, lab) in enumerate(labels):
                nxt = labels[i + 1][0] if i + 1 < len(labels) else 1e9
                s1 = max(o1, tm.out_clamped(lt))
                s2 = min(o2, tm.out_clamped(nxt) if nxt < 1e8 else o2)
                if lt <= a < nxt:
                    s1 = o1
                if s2 - s1 > 0.2:
                    lines.append(ev(2, s1, s2, 'HdrMuted', f'{{\\an6\\pos({ctx.W - sx(ctx, 40)},{ctx.strip//2})}}' + lab))
    lt_y = (ctx.H - sy(ctx, 280)) if captions else (ctx.H - sy(ctx, 116))
    callouts = ctx.callouts
    for i, (t, text, dur_) in enumerate(callouts):
        o1 = tm.out(t)
        if o1 is None:
            continue
        seg = tm.seg_of(t)
        nxt = callouts[i + 1][0] if i + 1 < len(callouts) else 1e9
        o2 = min(tm.out_clamped(min(t + dur_, nxt - 0.3)), seg['out'] + seg['len'])
        w = tw(text, ctx.fr, fs(ctx, 34)) + sx(ctx, 70)
        x1, y1 = sx(ctx, 60), lt_y
        x2, y2 = int(x1 + w + sx(ctx, 14)), lt_y + sy(ctx, 76)
        fad = '{\\fad(250,250)}'
        lines.append(ev(3, o1, o2, 'Box', fad + rect(x1, y1, x2, y2, '20120B', '30')))
        lines.append(ev(4, o1, o2, 'Box', fad + rect(x1, y1, x1 + sx(ctx, 10), y2, ctx.accent_ass)))
        lines.append(ev(5, o1, o2, 'LT', fad + f'{{\\an4\\pos({x1 + sx(ctx, 42)},{y1 + sy(ctx, 38)})}}' + text))
    for s in tl:
        if s['kind'] == 'src' and s['badge']:
            o1, o2 = s['out'], s['out'] + s['len']
            txt = f"{s['speed']}x  fast forward"
            w = tw(txt, ctx.fb, fs(ctx, 26)) + sx(ctx, 44)
            x2, y2 = ctx.W - sx(ctx, 60), ctx.H - sy(ctx, 40)
            x1, y1 = int(x2 - w), y2 - sy(ctx, 48)
            lines.append(ev(3, o1, o2, 'Box', rect(x1, y1, x2, y2, '20120B', '30')))
            lines.append(ev(5, o1, o2, 'Badge', f'{{\\an5\\pos({(x1+x2)//2},{(y1+y2)//2})}}' + txt))
    if captions:
        for a, b, cl in load_captions(ctx):
            o1, o2 = tm.out(a), tm.out_clamped(b)
            if o1 is None:
                o1 = tm.out_clamped(a)
            if o2 - o1 > 0.3:
                lines.append(ev(6, o1, o2, 'Cap', '\\N'.join(cl)))
    return ''.join(lines)


def clean(ctx, text):
    """Apply the plan's caption_fixes, then drop 'uh' and tidy the spaces."""
    fixes = list(ctx.caption_fixes) + [(r', uh,', ','), (r'\buh, ', ''), (r'\buh\b', ''), (r'  +', ' '), (r' ,', ',')]
    for pat, rep in fixes:
        text = re.sub(pat, rep, text)
    return text.strip()


def load_captions(ctx):
    """Cues from word timestamps: max 2 lines x 42 chars, break on pauses > 0.8 s, sentence ends, or 7 s."""
    words = load_words(ctx)
    cues, cur = [], []

    def flush():
        if not cur:
            return
        text = clean(ctx, ' '.join(w for _, _, w in cur))
        if len(text) < 3:
            cur.clear()
            return
        lines, line = [], ''
        for tok in text.split():
            if line and len(line) + 1 + len(tok) > 42:
                lines.append(line)
                line = tok
            else:
                line = (line + ' ' + tok).strip()
        if line:
            lines.append(line)
        cues.append((cur[0][0], cur[-1][1], lines))
        cur.clear()

    for a, b, w in words:
        if cur:
            gap = a - cur[-1][1]
            length = len(' '.join(x for _, _, x in cur)) + 1 + len(w)
            ends = cur[-1][2].endswith(('.', '?', '!'))
            if gap > 0.8 or length > 84 or (ends and length > 40) or (b - cur[0][0]) > 7.0:
                flush()
        cur.append((a, b, w))
    flush()
    merged = []  # fold cues of fewer than three words into their neighbour so no caption is a lone word
    for a, b, lines in cues:
        words_n = sum(len(l.split()) for l in lines)
        if words_n < 3 and merged and a - merged[-1][1] < 2.5:
            pa, pb, pl = merged[-1]
            text = ' '.join(pl) + ' ' + ' '.join(lines)
            nl, line = [], ''
            for tok in text.split():
                if line and len(line) + 1 + len(tok) > 42:
                    nl.append(line)
                    line = tok
                else:
                    line = (line + ' ' + tok).strip()
            if line:
                nl.append(line)
            merged[-1] = (pa, b, nl)
        else:
            merged.append((a, b, lines))
    cues = []
    for a, b, lines in merged:
        if cues and sum(len(l.split()) for l in cues[-1][2]) < 3 and a - cues[-1][1] < 2.5:
            pa, pb, pl = cues.pop()
            text = ' '.join(pl) + ' ' + ' '.join(lines)
            nl, line = [], ''
            for tok in text.split():
                if line and len(line) + 1 + len(tok) > 42:
                    nl.append(line)
                    line = tok
                else:
                    line = (line + ' ' + tok).strip()
            if line:
                nl.append(line)
            cues.append((pa, b, nl))
        else:
            cues.append((a, b, lines))

    def wrap(text):
        nl, line = [], ''
        for tok in text.split():
            if line and len(line) + 1 + len(tok) > 42:
                nl.append(line)
                line = tok
            else:
                line = (line + ' ' + tok).strip()
        return nl + ([line] if line else [])

    def split(a, b, lines):
        """A cue longer than two lines is halved by word count (never by chopping a trailing line off)."""
        if len(lines) <= 2:
            return [(a, b, lines)]
        ws = ' '.join(lines).split()
        h = len(ws) // 2
        m = a + (b - a) * h / len(ws)
        return split(a, m, wrap(' '.join(ws[:h]))) + split(m, b, wrap(' '.join(ws[h:])))

    out = []
    for a, b, lines in cues:
        out += split(a, b, lines)
    return out


def write_srt(ctx, tm):
    n, lines = 0, []

    def st(t):
        h = int(t // 3600)
        m = int(t % 3600 // 60)
        s = t % 60
        return f'{h:02d}:{m:02d}:{int(s):02d},{int((s % 1) * 1000):03d}'

    for a, b, cl in load_captions(ctx):
        o1, o2 = tm.out(a), tm.out_clamped(b)
        if o1 is None or o2 - o1 < 0.3:
            continue
        n += 1
        lines.append(f'{n}\n{st(o1)} --> {st(o2)}\n' + '\n'.join(cl) + '\n\n')
    open(f'{ctx.out}.srt', 'w').write(''.join(lines))
