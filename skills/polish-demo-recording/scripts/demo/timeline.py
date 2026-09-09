"""Turn the plan's ops (chapter cards, speed-ups, zooms) into an ordered segment list, group it into
pieces (source runs and cards), and map source seconds to output seconds after cuts and dissolves."""
from demo.ffmpeg import dur


def build_timeline(ctx):
    """Ordered segments: open card, source runs split at every op, chapter cards, end card."""
    assert ctx.brand.get('name') and ctx.src_end > ctx.src_start, 'plan.json needs brand.name, src_start and src_end'
    ops = []
    for i, c in enumerate(ctx.chapters, 1):
        ops.append((c['cut'], c.get('resume', c['cut']), 'card', i))
    for a, b, s, badge in ctx.speedups:
        ops.append((a + 0.5, b - 0.4, 'speed', (s, badge)))
    for a, b, z, cx, cy in ctx.zooms:
        ops.append((a, b, 'zoom', (z, cx, cy)))
    ops.sort()
    for i in range(1, len(ops)):
        assert ops[i][0] >= ops[i - 1][1], f'overlapping ops: {ops[i-1]} {ops[i]}'
    tl = [dict(kind='card', img='cards/open.png', dur=ctx.open_dur)]
    cur = ctx.src_start

    def src(a, b, speed=1, badge=False, zoom=None):
        if b - a > 0.05:
            tl.append(dict(kind='src', a=a, b=b, speed=speed, badge=badge, zoom=zoom))

    for a, b, kind, p in ops:
        src(cur, a)
        if kind == 'card':
            tl.append(dict(kind='card', img=f'cards/ch{p}.png', dur=ctx.card_dur, chapter=p))
            cur = b
        elif kind == 'speed':
            src(a, b, speed=p[0], badge=p[1])
            cur = b
        else:
            src(a, b, zoom=p)
            cur = b
    end = min(ctx.src_end, dur(ctx.master) - 0.05)
    if end < ctx.src_end:
        print(f'warning: src_end {ctx.src_end} is past the master ({dur(ctx.master):.2f}s); clamped to {end:.2f}')
    for a, b, kind, p in ops:
        assert b <= end, f'op {kind} {a}-{b} lies past the end of the master ({end:.2f}s)'
    src(cur, end)
    tl.append(dict(kind='card', img='cards/end.png', dur=ctx.end_dur))
    return tl


def build_pieces(tl):
    """Group consecutive source segments into runs; every card is its own piece."""
    pieces = []
    for s in tl:
        if s['kind'] == 'card':
            pieces.append(('card', [s]))
        elif pieces and pieces[-1][0] == 'run':
            pieces[-1][1].append(s)
        else:
            pieces.append(('run', [s]))
    return pieces


class TimeMap:
    """Source seconds to output seconds, including speed-ups and the dissolve overlaps."""

    def __init__(self, tl):
        self.tl = tl

    def seg_of(self, t):
        for s in self.tl:
            if s['kind'] == 'src' and s['a'] <= t < s['b']:
                return s
        return None

    def out(self, t):
        s = self.seg_of(t)
        if s is None:
            return None
        return s['out'] + (t - s['a']) / s['speed']

    def out_clamped(self, t):
        """Like out(), but a time inside a cut or a card maps to the end of the last segment before it."""
        best = 0.0
        for s in self.tl:
            if s['kind'] != 'src':
                continue
            if s['a'] <= t < s['b']:
                return s['out'] + (t - s['a']) / s['speed']
            if s['b'] <= t:
                best = s['out'] + s['len']
        return best
