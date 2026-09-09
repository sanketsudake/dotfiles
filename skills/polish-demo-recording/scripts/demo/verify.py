"""Verification: stream durations, integrated loudness and true peak, and verify.png built from direct -ss seeks
at every card, callout, badge, zoom (before/after pair at 1:1) and dissolve midpoint.

select=eq(n,..) contact sheets on the xfade output come out time-shifted; only direct seeks are trusted."""
import os
import re
import subprocess
from demo.ffmpeg import ff


def verify(ctx, tl, tm):
    """Direct -ss seeks only: select=eq(n,..) contact sheets come out time-shifted on xfade output."""
    name = f'{ctx.out}.mp4'
    print(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type,duration,r_frame_rate', '-of', 'csv=p=0', name]).decode())
    out = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', name, '-af', 'ebur128=peak=true', '-f', 'null', '-'], capture_output=True, text=True).stderr
    print('\n'.join(l for l in out.splitlines() if re.match(r'^\s+(I|LRA|Peak):', l)))
    times = [(s['out'] + s['len'] / 2, os.path.basename(s['img'])) for s in tl if s['kind'] == 'card']
    times += [(tm.out(t) + 1.0, 'callout') for t, _, _ in ctx.callouts if tm.out(t) is not None]
    times += [(s['out'] + s['len'] / 2, 'badge') for s in tl if s['kind'] == 'src' and s['badge']]
    times += [(s['out'] + s['len'] / 2, 'hold') for s in tl if s['kind'] == 'src' and s.get('hold')]
    zooms = [s for s in tl if s['kind'] == 'src' and s['zoom']]
    times += [(s['out'] - ctx.xf / 2, 'dissolve') for s in tl if s['kind'] == 'card' and s['out'] > 0]
    times.sort()
    os.makedirs('verify', exist_ok=True)
    files = []
    for i, (t, what) in enumerate(times):
        f = f'verify/{i:02d}.png'
        files.append(f)
        ff('-ss', f'{t:.3f}', '-i', name, '-frames:v', '1', '-vf', f"scale=640:-1,drawtext=text='{t:.1f}s {what}':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f)
    # zooms are subtle by design (z <= 1.3): show the same region before (master) and after (final) at 1:1
    for i, s in enumerate(zooms):
        z, cx, cy = s['zoom']
        mid_src = s['a'] + (s['b'] - s['a']) / 2
        mid_out = s['out'] + s['len'] / 2
        cw, chh = 640, 360
        ff('-ss', f'{mid_src:.3f}', '-i', ctx.master, '-frames:v', '1', '-vf', f"crop={cw}:{chh}:{max(0, min(cx - cw // 2, ctx.W - cw))}:{max(0, min(cy - chh // 2, ctx.H - chh))},drawtext=text='zoom {i+1} before, 1 to 1':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f'verify/z{i:02d}a.png')
        ff('-ss', f'{mid_out:.3f}', '-i', name, '-frames:v', '1', '-vf', f"crop={cw}:{chh}:{(ctx.W - cw) // 2}:{(ctx.H - chh) // 2},drawtext=text='zoom {i+1} after x{z}, 1 to 1':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6", f'verify/z{i:02d}b.png')
        files += [f'verify/z{i:02d}a.png', f'verify/z{i:02d}b.png']
    cols = 4
    rows = (len(files) + cols - 1) // cols
    # simple, robust tiling: pad the list to a full grid then tile via concat of rows
    row_files = []
    for r in range(rows):
        chunk = files[r * cols:(r + 1) * cols]
        while len(chunk) < cols:
            if not os.path.exists('verify/blank.png'):
                ff('-f', 'lavfi', '-i', f'color=c=black:s=640x360', '-frames:v', '1', 'verify/blank.png')
            chunk.append('verify/blank.png')
        rf = f'verify/row{r}.png'
        ff(*sum([['-i', f] for f in chunk], []), '-filter_complex', f'{"".join(f"[{i}]" for i in range(cols))}hstack=inputs={cols}', rf)
        row_files.append(rf)
    if len(row_files) == 1:
        os.replace(row_files[0], 'verify.png')
    else:
        ff(*sum([['-i', f] for f in row_files], []), '-filter_complex', f'{"".join(f"[{i}]" for i in range(len(row_files)))}vstack=inputs={len(row_files)}', 'verify.png')
    print(f'verify.png: {len(files)} frames (cards, callouts, badges, zooms, dissolves). Read it and check each one.')
