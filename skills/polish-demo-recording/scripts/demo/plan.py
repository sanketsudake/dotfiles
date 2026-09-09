"""Read plan.json (schema v2), validate it, and build the Ctx every stage reads.

Ctx carries normalized values (tuples, resolved paths, defaults applied). No other module reads the raw plan,
so a schema change lands here and nowhere else. See ../../references/plan-schema.md for every key.
"""
import json
import os
import sys
from dataclasses import dataclass
from demo.fonts import resolve as resolve_fonts

SCHEMA_VERSION = 2
TOP_KEYS = {
    'schema_version', 'workdir', 'sources', 'voice', 'voice_wav', 'transcript', 'video', 'brand', 'range',
    'first_label', 'chapters', 'labels', 'speedups', 'zooms', 'cuts', 'holds', 'callouts', 'callout_dur',
    'caption_fixes', 'captions', 'music', 'timing', 'out_prefix',
}
STRIP_MODES = ('crop', 'pad', 'none')


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def validate(plan, base_dir):
    """Return a list of 'json.path: rule' strings; empty means valid. Checks shapes, ranges and file presence."""
    e = []

    def need(obj, path, keys):
        for k in keys:
            if k not in obj:
                e.append(f'{path}.{k}: required')

    def num_range(v, path, lo, hi):
        if not _num(v):
            e.append(f'{path}: must be a number, got {v!r}')
        elif not lo <= v <= hi:
            e.append(f'{path}: must be {lo}..{hi}, got {v}')

    def span(o, path, a='from', b='to'):
        if _num(o.get(a)) and _num(o.get(b)) and o[b] <= o[a]:
            e.append(f'{path}: {b} must be greater than {a}')

    def exists(p, path):
        if isinstance(p, str) and not os.path.exists(os.path.join(base_dir, p)):
            e.append(f'{path}: file not found: {p}')

    if not isinstance(plan, dict):
        return ['plan: must be a JSON object']
    if plan.get('schema_version') != SCHEMA_VERSION:
        e.append(f'schema_version: must be {SCHEMA_VERSION} (positional v1 plans are not read; see references/plan-schema.md)')
    for k in sorted(set(plan) - TOP_KEYS):
        e.append(f'{k}: unknown key')
    need(plan, 'plan', ['sources', 'brand', 'out_prefix'])
    srcs = plan.get('sources')
    if not isinstance(srcs, list) or not srcs:
        e.append('sources: must be a non-empty list')
    else:
        for i, s in enumerate(srcs):
            if not isinstance(s, dict) or 'path' not in s:
                e.append(f'sources[{i}]: must be an object with "path"')
                continue
            exists(s['path'], f'sources[{i}].path')
            for k in ('start', 'end'):
                if k in s and not _num(s[k]):
                    e.append(f'sources[{i}].{k}: must be a number')
            if _num(s.get('start')) and _num(s.get('end')) and s['end'] <= s['start']:
                e.append(f'sources[{i}]: end must be greater than start')
    voice = plan.get('voice', 'embedded')
    if voice == 'none':
        if plan.get('transcript') is not None:
            e.append('transcript: must be null when voice is "none"')
    elif isinstance(voice, dict):
        need(voice, 'voice', ['path'])
        exists(voice.get('path'), 'voice.path')
        if 'offset' in voice and not _num(voice['offset']):
            e.append('voice.offset: must be a number (seconds; the master time at which the track starts, negative when the track starts early)')
    elif voice != 'embedded':
        e.append('voice: must be "embedded", "none", or {"path": ..., "offset": ...}')
    brand = plan.get('brand')
    if not isinstance(brand, dict) or not brand.get('name'):
        e.append('brand.name: required')
    video = plan.get('video', {})
    if not isinstance(video, dict):
        e.append('video: must be an object')
        video = {}
    for k, lo, hi in (('width', 320, 7680), ('height', 320, 4320), ('fps', 10, 120), ('chrome_top', 0, 1000)):
        if k in video:
            num_range(video[k], f'video.{k}', lo, hi)
    strip = video.get('strip', {})
    if not isinstance(strip, dict):
        e.append('video.strip: must be an object')
        strip = {}
    mode = strip.get('mode', 'crop')
    if mode not in STRIP_MODES:
        e.append(f'video.strip.mode: must be one of {STRIP_MODES}, got {mode!r}')
    if 'height' in strip:
        num_range(strip['height'], 'video.strip.height', 0, 1000)
    if mode == 'crop' and 'height' in strip and 'chrome_top' in video and strip['height'] != video['chrome_top']:
        e.append('video.strip.height: in crop mode the strip replaces the chrome, so it must equal video.chrome_top')
    rng = plan.get('range')
    if not isinstance(rng, dict):
        e.append('range: required, {"start": s, "end": s}')
    else:
        need(rng, 'range', ['start', 'end'])
        span(rng, 'range', 'start', 'end')
    def items(key):
        """Yield (index, item) for a list of objects; a non-object item (a v1 positional array) is reported and skipped."""
        lst = plan.get(key, [])
        if not isinstance(lst, list):
            e.append(f'{key}: must be a list')
            return
        for i, it in enumerate(lst):
            if isinstance(it, dict):
                yield i, it
            else:
                e.append(f'{key}[{i}]: must be an object (v1 positional arrays are not read)')

    lo, hi = None, None
    if isinstance(rng, dict) and _num(rng.get('start')) and _num(rng.get('end')):
        lo, hi = rng['start'], rng['end']

    def inside(t, path):
        if lo is not None and _num(t) and not lo <= t <= hi:
            e.append(f'{path}: {t} lies outside range {lo}..{hi}')

    ops = []  # (start, end, path) on the master axis, the same windows timeline.build_timeline uses
    for i, c in items('chapters'):
        need(c, f'chapters[{i}]', ['cut', 'title'])
        if 'resume' in c and _num(c.get('cut')) and _num(c['resume']) and c['resume'] < c['cut']:
            e.append(f'chapters[{i}].resume: must not be before cut')
        if _num(c.get('cut')):
            inside(c['cut'], f'chapters[{i}].cut')
            ops.append((c['cut'], c.get('resume', c['cut']) if _num(c.get('resume')) else c['cut'], f'chapters[{i}]'))
    for i, l in items('labels'):
        need(l, f'labels[{i}]', ['at', 'text'])
        inside(l.get('at'), f'labels[{i}].at')
    for i, s in items('speedups'):
        need(s, f'speedups[{i}]', ['from', 'to', 'factor'])
        span(s, f'speedups[{i}]')
        if 'factor' in s:
            num_range(s['factor'], f'speedups[{i}].factor', 1.5, 8)
        if _num(s.get('from')) and _num(s.get('to')):
            inside(s['from'], f'speedups[{i}].from')
            inside(s['to'], f'speedups[{i}].to')
            ops.append((s['from'] + 0.5, s['to'] - 0.4, f'speedups[{i}]'))
    for i, z in items('zooms'):
        need(z, f'zooms[{i}]', ['from', 'to', 'factor', 'cx', 'cy'])
        span(z, f'zooms[{i}]')
        if 'factor' in z:
            num_range(z['factor'], f'zooms[{i}].factor', 1.0, 2.0)
        if _num(z.get('from')) and _num(z.get('to')):
            inside(z['from'], f'zooms[{i}].from')
            inside(z['to'], f'zooms[{i}].to')
            ops.append((z['from'], z['to'], f'zooms[{i}]'))
    for i, c in items('cuts'):
        need(c, f'cuts[{i}]', ['from', 'to'])
        span(c, f'cuts[{i}]')
        if _num(c.get('from')) and _num(c.get('to')):
            inside(c['from'], f'cuts[{i}].from')
            inside(c['to'], f'cuts[{i}].to')
            ops.append((c['from'], c['to'], f'cuts[{i}]'))
    for i, h in items('holds'):
        need(h, f'holds[{i}]', ['at', 'dur'])
        if 'dur' in h:
            num_range(h['dur'], f'holds[{i}].dur', 0.2, 30)
        if _num(h.get('at')) and _num(h.get('dur')):
            inside(h['at'], f'holds[{i}].at')
            inside(h['at'] + h['dur'], f'holds[{i}].at+dur')
            ops.append((h['at'], h['at'] + h['dur'], f'holds[{i}]'))
    for i, c in items('callouts'):
        need(c, f'callouts[{i}]', ['at', 'text'])
        inside(c.get('at'), f'callouts[{i}].at')
        if 'text' in c and len(str(c['text'])) > 60:
            e.append(f'callouts[{i}].text: longer than 60 characters')
    for i, f in items('caption_fixes'):
        need(f, f'caption_fixes[{i}]', ['find', 'replace'])
    ops.sort()
    for (a1, b1, p1), (a2, b2, p2) in zip(ops, ops[1:]):
        if a2 < b1:
            e.append(f'{p2}: overlaps {p1} ({a1}..{b1} and {a2}..{b2})')
    caps = plan.get('captions', {})
    if 'max_width_frac' in caps:
        num_range(caps['max_width_frac'], 'captions.max_width_frac', 0.3, 1.0)
    music = plan.get('music')
    if music is not None:
        if not isinstance(music, dict) or 'path' not in music:
            e.append('music: must be null or {"path": ..., "volume": ...}')
        else:
            exists(music['path'], 'music.path')
            if 'volume' in music:
                num_range(music['volume'], 'music.volume', 0.0, 1.0)
    for k in ('card_dur', 'open_dur', 'end_dur', 'xfade'):
        if k in plan.get('timing', {}):
            num_range(plan['timing'][k], f'timing.{k}', 0.1, 30)
    if 'transcript' in plan and plan['transcript'] is not None:
        exists(plan['transcript'], 'transcript')
    return e


@dataclass
class Ctx:
    plan: dict
    work: str
    W: int
    H: int
    fps: int
    chrome_top: int
    strip_mode: str
    strip: int
    strip_color: str
    master: str
    brand: dict
    fb: str
    fr: str
    font_family: str
    font_dir: str
    accent: tuple
    ink: tuple
    muted: tuple
    bg: tuple
    light: tuple
    accent_ass: str
    src_start: float
    src_end: float
    card_dur: float
    open_dur: float
    end_dur: float
    xf: float
    callout_dur: float
    out: str
    sources: list
    voice_wav: str
    voice_mode: str
    voice_path: str
    voice_offset: float
    transcript: str
    first_label: str
    chapters: list
    labels: list
    speedups: list
    zooms: list
    cuts: list
    holds: list
    callouts: list
    caption_fixes: list
    music: dict
    cap_max_frac: float


def build(plan, work):
    """Normalize a validated v2 plan into a Ctx (defaults applied, ops as tuples)."""
    brand = plan['brand']
    video = plan.get('video', {})
    if 'width' not in video or 'height' not in video:
        from demo.sources import probe  # local import: sources imports ffmpeg only, but keep plan.py free of a module-level cycle
        info = probe(plan['sources'][0]['path'])
        video = dict(video, width=video.get('width', info['width']), height=video.get('height', info['height']))
    height = int(video['height'])
    strip = video.get('strip', {})
    mode = strip.get('mode', 'crop')
    chrome_top = int(video.get('chrome_top', 0))
    if mode == 'crop':
        strip_h = chrome_top
    elif mode == 'pad':
        strip_h = int(strip.get('height', round(64 * height / 1080)))
    else:
        strip_h = 0
    face = resolve_fonts(brand.get('fonts'))
    accent = hexrgb(brand.get('accent', '#3b5bfd'))
    timing = plan.get('timing', {})
    callout_dur = float(plan.get('callout_dur', 5.0))
    voice = plan.get('voice', 'embedded')
    if voice == 'none':
        voice_mode, voice_path, voice_offset = 'none', None, 0.0
    elif isinstance(voice, dict):
        voice_mode, voice_path, voice_offset = 'file', voice['path'], float(voice.get('offset', 0.0))
    else:
        voice_mode, voice_path, voice_offset = 'embedded', None, 0.0
    return Ctx(
        plan=plan,
        work=work,
        W=int(video.get('width', 1920)),
        H=int(height),
        fps=int(video.get('fps', 30)),
        chrome_top=chrome_top,
        strip_mode=mode,
        strip=strip_h,
        strip_color=strip.get('color', '0b1220'),
        master='master.mov',
        brand=brand,
        fb=face.bold,
        fr=face.regular,
        font_family=face.family,
        font_dir=face.dir,
        accent=accent,
        ink=hexrgb(brand.get('ink', '#0b1220')),
        muted=hexrgb(brand.get('muted', '#788296')),
        bg=hexrgb(brand.get('card_bg', '#f8fafc')),
        light=hexrgb(brand.get('light', '#d5d9e2')),
        accent_ass='%02X%02X%02X' % (accent[2], accent[1], accent[0]),  # ASS colours are BGR
        src_start=float(plan['range']['start']),
        src_end=float(plan['range']['end']),
        card_dur=float(timing.get('card_dur', 2.4)),
        open_dur=float(timing.get('open_dur', 3.2)),
        end_dur=float(timing.get('end_dur', 5.0)),
        xf=float(timing.get('xfade', 0.45)),
        callout_dur=callout_dur,
        out=plan['out_prefix'],
        sources=list(plan['sources']),
        voice_wav=plan.get('voice_wav', 'voice.wav'),
        voice_mode=voice_mode,
        voice_path=voice_path,
        voice_offset=voice_offset,
        transcript=plan.get('transcript'),
        first_label=plan.get('first_label', 'Welcome'),
        chapters=list(plan.get('chapters', [])),
        labels=[(float(l['at']), str(l['text'])) for l in plan.get('labels', [])],
        speedups=[(float(s['from']), float(s['to']), s['factor'], bool(s.get('badge', False))) for s in plan.get('speedups', [])],
        zooms=[(float(z['from']), float(z['to']), z['factor'], z['cx'], z['cy']) for z in plan.get('zooms', [])],
        cuts=[(float(c['from']), float(c['to'])) for c in plan.get('cuts', [])],
        holds=[(float(h['at']), float(h['dur'])) for h in plan.get('holds', [])],
        callouts=[(float(c['at']), str(c['text']), float(c.get('dur', callout_dur))) for c in plan.get('callouts', [])],
        caption_fixes=[(f['find'], f['replace']) for f in plan.get('caption_fixes', [])],
        music=plan.get('music'),
        cap_max_frac=float(plan.get('captions', {}).get('max_width_frac', 0.8)),
    )


def load(path):
    """Read, validate (exit 2 with one 'path: rule' line per error), enter the work dir, and build the Ctx."""
    plan = json.load(open(path))
    work = os.path.abspath(plan.get('workdir', os.path.dirname(os.path.abspath(path))) if isinstance(plan, dict) else '.')
    errors = validate(plan, work)
    if errors:
        print('plan.json is not valid:', file=sys.stderr)
        for line in errors:
            print('  ' + line, file=sys.stderr)
        sys.exit(2)
    os.makedirs(work, exist_ok=True)
    os.chdir(work)
    return build(plan, work)
