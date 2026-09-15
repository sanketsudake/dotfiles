"""Verification: stream durations, integrated loudness and true peak, and verify.png built from direct -ss seeks
at every card, callout, badge, zoom (before/after pair at 1:1) and dissolve midpoint.

select=eq(n,..) contact sheets on the xfade output come out time-shifted; only direct seeks are trusted."""
import json
import os
import re
import subprocess
from demo.ffmpeg import ff

AV_TOLERANCE = 0.05  # seconds; video and audio of the deliverable must end together


def visible_point(tm, a, b):
    """Output time at the middle of the longest part of a..b that is in the output, or None when no part of it is.

    Exact intersection with the timeline's source segments, not sampling: a redaction may straddle a cut, and the part
    that survives can be shorter than any sampling step (1.00..1.09 with a cut 1.00..1.05 keeps 1.05..1.09)."""
    best = None
    for s in tm.tl:
        if s['kind'] != 'src':
            continue
        lo, hi = max(a, s['a']), min(b, s['b'])
        if hi > lo and (best is None or hi - lo > best[1] - best[0]):
            best = (lo, hi)
    return None if best is None else tm.out((best[0] + best[1]) / 2)


def cell_size(ctx, width=640):
    """Every contact-sheet cell shares one even-sized canvas in the frame's aspect, so hstack/vstack always match."""
    h = int(round(width * ctx.H / ctx.W))
    return width, h + (h % 2)


def verify(ctx, tl, tm):
    """Direct -ss seeks only: select=eq(n,..) contact sheets come out time-shifted on xfade output."""
    name = f'{ctx.out}.mp4'
    cw, chh = cell_size(ctx)
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type,duration,r_frame_rate', '-of', 'json', name]))
    durs = {}
    for s in info['streams']:
        durs[s['codec_type']] = float(s.get('duration', 'nan'))
        print(f"{s['codec_type']}: {durs[s['codec_type']]:.3f}s" + (f", {s['r_frame_rate']} fps" if s['codec_type'] == 'video' else ''))
    if 'video' in durs and 'audio' in durs:
        delta = abs(durs['video'] - durs['audio'])
        ok = delta <= AV_TOLERANCE
        print(('' if ok else 'warning: ') + f'streams: video {durs["video"]:.3f}s, audio {durs["audio"]:.3f}s, '
              + (f'within {AV_TOLERANCE * 1000:.0f} ms' if ok else f'differ by {delta * 1000:.0f} ms (limit {AV_TOLERANCE * 1000:.0f} ms)'))
    else:
        print('warning: streams: the deliverable does not carry both a video and an audio stream')
    out = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', name, '-af', 'ebur128=peak=true', '-f', 'null', '-'], capture_output=True, text=True).stderr
    print('\n'.join(l for l in out.splitlines() if re.match(r'^\s+(I|LRA|Peak):', l)))
    m = re.search(r'^\s+I:\s+(-?[\d.]+) LUFS', out, re.M)
    if m:
        measured = float(m.group(1))
        diff = measured - ctx.loudness_target
        flag = 'ok' if abs(diff) <= 1.0 else f'off by {diff:+.1f} LU'
        print(('' if abs(diff) <= 1.0 else 'warning: ') + f'loudness: I {measured} LUFS, target {ctx.loudness_target:g} ({flag})')
    times = [(s['out'] + s['len'] / 2, os.path.basename(s['img'])) for s in tl if s['kind'] == 'card']
    times += [(tm.out(t) + 1.0, 'callout') for t, _, _ in ctx.callouts if tm.out(t) is not None]
    times += [(s['out'] + s['len'] / 2, 'badge') for s in tl if s['kind'] == 'src' and s['badge']]
    times += [(s['out'] + s['len'] / 2, 'hold') for s in tl if s['kind'] == 'src' and s.get('hold')]
    times += [(s['out'] + s['len'] / 2, 'bumper') for s in tl if s['kind'] == 'bumper']
    for a, b, *_ in ctx.redactions:
        t = visible_point(tm, a, b)
        if t is None:
            print(f'warning: redaction {a:g}-{b:g} lies entirely inside a cut; nothing of it is in the output')
        else:
            times.append((t, 'redaction'))
    zooms = [s for s in tl if s['kind'] == 'src' and s['zoom']]
    times += [(s['out'] - ctx.xf / 2, 'dissolve') for s in tl if s['kind'] in ('card', 'bumper') and s['out'] > 0]
    times.sort()
    os.makedirs('verify', exist_ok=True)
    files = []
    for i, (t, what) in enumerate(times):
        f = f'verify/{i:02d}.png'
        files.append(f)
        ff('-ss', f'{t:.3f}', '-i', name, '-frames:v', '1', '-vf', f"scale={cw}:{chh},drawtext=text='{t:.1f}s {what}':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f)
    # zooms are subtle by design (z <= 1.3): show the same region before (master) and after (final) at 1:1
    for i, s in enumerate(zooms):
        z, cx, cy = s['zoom']
        mid_src = s['a'] + (s['b'] - s['a']) / 2
        mid_out = s['out'] + s['len'] / 2
        # The 1:1 crop cannot exceed the frame (a portrait frame is narrower than the cell); pad it back to the cell.
        zw, zh = min(cw, ctx.W), min(chh, ctx.H)
        fit = f',pad={cw}:{chh}:(ow-iw)/2:(oh-ih)/2' if (zw, zh) != (cw, chh) else ''
        ff('-ss', f'{mid_src:.3f}', '-i', ctx.master, '-frames:v', '1', '-vf', f"crop={zw}:{zh}:{max(0, min(cx - zw // 2, ctx.W - zw))}:{max(0, min(cy - zh // 2, ctx.H - zh))}{fit},drawtext=text='zoom {i+1} before, 1 to 1':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f'verify/z{i:02d}a.png')
        ff('-ss', f'{mid_out:.3f}', '-i', name, '-frames:v', '1', '-vf', f"crop={zw}:{zh}:{(ctx.W - zw) // 2}:{(ctx.H - zh) // 2}{fit},drawtext=text='zoom {i+1} after x{z}, 1 to 1':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f'verify/z{i:02d}b.png')
        files += [f'verify/z{i:02d}a.png', f'verify/z{i:02d}b.png']
    cols = 4
    rows = (len(files) + cols - 1) // cols
    # simple, robust tiling: pad the list to a full grid then tile via concat of rows
    row_files = []
    for r in range(rows):
        chunk = files[r * cols:(r + 1) * cols]
        while len(chunk) < cols:
            if not os.path.exists('verify/blank.png'):
                ff('-f', 'lavfi', '-i', f'color=c=black:s={cw}x{chh}', '-frames:v', '1', 'verify/blank.png')
            chunk.append('verify/blank.png')
        rf = f'verify/row{r}.png'
        ff(*sum([['-i', f] for f in chunk], []), '-filter_complex', f'{"".join(f"[{i}]" for i in range(cols))}hstack=inputs={cols}', rf)
        row_files.append(rf)
    if len(row_files) == 1:
        os.replace(row_files[0], 'verify.png')
    else:
        ff(*sum([['-i', f] for f in row_files], []), '-filter_complex', f'{"".join(f"[{i}]" for i in range(len(row_files)))}vstack=inputs={len(row_files)}', 'verify.png')
    print(f'verify.png: {len(files)} frames (cards, callouts, badges, zooms, dissolves). Read it and check each one.')
