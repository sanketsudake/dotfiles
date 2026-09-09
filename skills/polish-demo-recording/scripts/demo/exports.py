"""Opt-in deliverables next to the main files: .vtt and .txt transcripts, a YouTube chapter list plus mp4 chapter
metadata, a downscaled copy, and a short preview clip. Everything here runs after `final` and reads output time."""
import os
from demo.ffmpeg import dur, ff
from demo.overlays import cues


def _vtt_ts(t):
    ms = int(round(t * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f'{h:02d}:{m:02d}:{s:02d}.{ms:03d}'


def _mmss(t):
    """YouTube chapter time: MM:SS, or H:MM:SS past an hour."""
    t = int(t)
    h, rest = divmod(t, 3600)
    m, s = divmod(rest, 60)
    return f'{h}:{m:02d}:{s:02d}' if h else f'{m:02d}:{s:02d}'


def write_vtt(ctx, tm):
    lines = ['WEBVTT', '']
    for i, (a, b, cl) in enumerate(cues(ctx, tm), 1):
        lines += [str(i), f'{_vtt_ts(a)} --> {_vtt_ts(b)}', *cl, '']
    open(f'{ctx.out}.vtt', 'w').write('\n'.join(lines))


def write_txt(ctx, tm):
    lines = [f'[{_mmss(a)}] ' + ' '.join(cl) for a, b, cl in cues(ctx, tm)]
    open(f'{ctx.out}.txt', 'w').write('\n'.join(lines) + '\n')


def write_chapters(ctx, tl, tm):
    """YouTube form (`MM:SS Title`, first at 00:00) and an ffmetadata file for mp4 chapters. Returns the ffmeta path."""
    marks = [(0.0, ctx.brand['name'])]
    for s in tl:
        if s['kind'] == 'card' and s.get('chapter'):
            marks.append((s['out'], ctx.chapters[s['chapter'] - 1]['title']))
    total = dur(f'{ctx.out}.mp4')
    open(f'{ctx.out}-chapters.txt', 'w').write('\n'.join(f'{_mmss(t)} {title}' for t, title in marks) + '\n')
    meta = [';FFMETADATA1']
    for i, (t, title) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else total
        meta += ['[CHAPTER]', 'TIMEBASE=1/1000', f'START={int(t * 1000)}', f'END={int(end * 1000)}', f'title={title}']
    path = f'{ctx.out}-chapters.ffmeta'
    open(path, 'w').write('\n'.join(meta) + '\n')
    return path


def mux_chapters(name, ffmeta):
    """Add the chapters to an existing mp4 without re-encoding (the file is replaced in place)."""
    tmp = name + '.chapters.mp4'
    ff('-i', name, '-i', ffmeta, '-map_metadata', '1', '-map_chapters', '1', '-c', 'copy', '-movflags', '+faststart', tmp)
    os.replace(tmp, name)


def downscale(ctx, src, height):
    name = f'{ctx.out}-{height}p.mp4'
    ff('-i', src, '-vf', f'scale=-2:{height}', '-c:v', 'libx264', '-crf', '20', '-preset', 'medium', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-c:a', 'copy', name)
    print('wrote', name, dur(name), flush=True)


def preview(ctx, src, a, b):
    name = f'{ctx.out}-preview.mp4'
    ff('-ss', f'{a:.3f}', '-t', f'{b - a:.3f}', '-i', src, '-c:v', 'libx264', '-crf', '20', '-preset', 'medium', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-c:a', 'aac', '-b:a', '128k', name)
    print('wrote', name, dur(name), flush=True)


def run(ctx, tl, tm):
    """Every export the plan asks for, after the final files exist."""
    ex = ctx.exports
    main = f'{ctx.out}.mp4'
    if ctx.transcript and 'vtt' in ex['formats']:
        write_vtt(ctx, tm)
    if ctx.transcript and 'txt' in ex['formats']:
        write_txt(ctx, tm)
    if 'chapters' in ex['formats']:
        ffmeta = write_chapters(ctx, tl, tm)
        for name in (main, f'{ctx.out}-captions.mp4', f'{ctx.out}-no-music.mp4'):
            if os.path.exists(name):
                mux_chapters(name, ffmeta)
    if ex['height']:
        downscale(ctx, main, int(ex['height']))
    if ex['preview']:
        preview(ctx, main, float(ex['preview']['from']), float(ex['preview']['to']))
