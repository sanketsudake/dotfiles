"""Render stages: the normalized master, the Pillow cards, the per-segment encodes, the concat with dissolves, and the final mix.

See ../../references/ffmpeg-recipes.md for why each parameter is what it is.
"""
import os
from PIL import Image, ImageDraw, ImageFont
from demo.ffmpeg import AENC, dur, ff, venc
from demo.timeline import build_pieces


def font(p, s):
    return ImageFont.truetype(p, s)


def tw(text, p, s):
    return font(p, s).getlength(text)


def master(ctx):
    raw = ctx.plan['raw']
    voice = ctx.plan['voice_wav']
    vf = f'fps={ctx.fps}'
    if ctx.strip:
        vf += f',crop={ctx.W}:{ctx.H - ctx.strip}:0:{ctx.strip},pad={ctx.W}:{ctx.H}:0:{ctx.strip}:color=0x{ctx.strip_color}'
    vf += ',format=yuv420p'
    ff('-i', raw, '-vf', vf, '-an', '-c:v', 'libx264', '-crf', '15', '-preset', 'fast', '-pix_fmt', 'yuv420p', 'master_v.mp4')
    ff('-i', 'master_v.mp4', '-i', voice, '-c:v', 'copy', '-c:a', 'pcm_s16le', '-shortest', ctx.master)
    print('master.mov', dur(ctx.master))


def rounded(d, box, r, fill, outline=None):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=2)


def make_cards(ctx):
    os.makedirs('cards', exist_ok=True)
    for i, c in enumerate(ctx.plan.get('chapters', []), 1):
        im = Image.new('RGB', (ctx.W, ctx.H), ctx.bg)
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 16, ctx.H], fill=ctx.accent)
        d.text((150, 110), ctx.brand['name'], font=font(ctx.fb, 52), fill=ctx.accent)
        d.text((156, 330), 'CHAPTER', font=font(ctx.fr, 40), fill=ctx.muted)
        d.text((150, 360), f'{i:02d}', font=font(ctx.fb, 200), fill=ctx.light)
        d.text((156, 620), c['title'], font=font(ctx.fb, 96), fill=ctx.ink)
        d.rectangle([160, 770, 600, 780], fill=ctx.accent)
        if c.get('subtitle'):
            d.text((160, 815), c['subtitle'], font=font(ctx.fr, 40), fill=ctx.muted)
        im.save(f'cards/ch{i}.png')
    im = Image.new('RGB', (ctx.W, ctx.H), ctx.bg)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 16, ctx.H], fill=ctx.accent)
    d.text((150, 110), ctx.brand.get('subtitle', 'Product demo'), font=font(ctx.fr, 40), fill=ctx.muted)
    d.text((146, 300), ctx.brand['name'], font=font(ctx.fb, 180), fill=ctx.accent)
    if ctx.brand.get('tagline'):
        d.text((156, 520), ctx.brand['tagline'], font=font(ctx.fb, 58), fill=ctx.ink)
    if ctx.brand.get('blurb'):
        d.text((158, 605), ctx.brand['blurb'], font=font(ctx.fr, 36), fill=ctx.muted)
    tiles = ctx.brand.get('tiles', [])
    if tiles:
        x, y, th, gap = 160, 760, 150, 22
        tw_ = int((ctx.W - 320 - gap * (len(tiles) - 1)) / len(tiles))
        for t, s in tiles:
            rounded(d, [x, y, x + tw_, y + th], 18, (255, 255, 255), outline=(226, 230, 238))
            d.rectangle([x, y, x + 6, y + th], fill=ctx.accent)
            d.text((x + 28, y + 36), t, font=font(ctx.fb, 30), fill=ctx.ink)
            d.text((x + 28, y + 84), s, font=font(ctx.fr, 24), fill=ctx.muted)
            x += tw_ + gap
    if ctx.brand.get('footer'):
        d.text((160, 980), ctx.brand['footer'], font=font(ctx.fb, 34), fill=ctx.ink)
    im.save('cards/open.png')
    im = Image.new('RGB', (ctx.W, ctx.H), ctx.bg)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 16, ctx.H], fill=ctx.accent)
    d.text((150, 110), ctx.brand['name'], font=font(ctx.fb, 52), fill=ctx.accent)
    d.text((150, 360), ctx.brand.get('end_title', 'Thank you'), font=font(ctx.fb, 150), fill=ctx.ink)
    d.rectangle([160, 560, 600, 570], fill=ctx.accent)
    for k, line in enumerate(ctx.brand.get('end_lines', [])):
        d.text((160, 610 + 55 * k), line, font=font(ctx.fr, 40), fill=ctx.muted)
    if ctx.brand.get('footer'):
        d.text((160, 980), ctx.brand['footer'], font=font(ctx.fb, 34), fill=ctx.ink)
    im.save('cards/end.png')


def zoom_vf(ctx, z, cx, cy, D):
    """Eased push-in (smoothstep, 0.7 s in/out) on the content area only; the strip is cropped off and padded back."""
    e = f'min(1,max(0,min(t/0.7,({D:.3f}-t)/0.7)))'
    E = f'(({e})*({e})*(3-2*({e})))'
    Z = f'(1+{z-1:.3f}*{E})'
    ch = ctx.H - ctx.strip
    cyc = cy - ctx.strip
    return (f'crop={ctx.W}:{ch}:0:{ctx.strip},'
            f"scale=w='trunc({ctx.W}*{Z}/2)*2':h='trunc({ch}*{Z}/2)*2':eval=frame,"
            f"crop={ctx.W}:{ch}:x='min(max({cx}*{Z}-{ctx.W/2},0),iw-{ctx.W})':y='min(max({cyc}*{Z}-{ch/2},0),ih-{ch})',"
            f'pad={ctx.W}:{ctx.H}:0:{ctx.strip}:color=0x{ctx.strip_color}')


def render_segs(ctx, tl, rerender):
    """Encode every timeline segment (cards, cuts, speed-ups, zooms) with identical settings.

    A segment file that already exists is reused unless rerender is set. Fills file, len and out
    (output-time start, accounting for one dissolve overlap per piece boundary) on each segment
    and returns the chained length.
    """
    os.makedirs('seg', exist_ok=True)
    for i, s in enumerate(tl):
        out = f'seg/{i:03d}.mp4'
        s['file'] = out
        if os.path.exists(out) and not rerender:
            continue
        if s['kind'] == 'card':
            ff('-loop', '1', '-framerate', str(ctx.fps), '-t', str(s['dur']), '-i', s['img'],
               '-f', 'lavfi', '-t', str(s['dur']), '-i', 'anullsrc=r=48000:cl=stereo',
               '-vf', f'scale={ctx.W}:{ctx.H},format=yuv420p', '-t', str(s['dur']), *venc(ctx.fps), *AENC, out)
        else:
            D = s['b'] - s['a']
            vf = f'fps={ctx.fps}'
            af = 'anull'
            if s['speed'] != 1:
                vf = f"setpts=PTS/{s['speed']},fps={ctx.fps}"
                af = f"atempo={s['speed']},volume=0"
            if s['zoom']:
                vf = f'fps={ctx.fps},' + zoom_vf(ctx, *s['zoom'], D)
            ff('-ss', f"{s['a']:.3f}", '-t', f'{D:.3f}', '-i', ctx.master, '-vf', vf, '-af', af, *venc(ctx.fps), *AENC, out)
        print(f"{out} {s['kind']} {s.get('a', '')}-{s.get('b', '')} x{s.get('speed', '')}", flush=True)
    for s in tl:
        s['len'] = dur(s['file'])
        assert s['len'] > 0, f"segment {s['file']} is empty: {s}"
    chain = 0.0
    for k, (kind, segs) in enumerate(build_pieces(tl)):
        t = chain - (ctx.xf if k > 0 else 0.0)
        for s in segs:
            s['out'] = t
            t += s['len']
        chain = t
    return chain


def concat(ctx, tl):
    """Join consecutive source segments with -c copy, then one xfade/acrossfade chain across every card boundary."""
    files = []
    for k, (kind, segs) in enumerate(build_pieces(tl)):
        if kind == 'card':
            files.append(segs[0]['file'])
            continue
        lst = f'seg/run{k:02d}.txt'
        out = f'seg/run{k:02d}.mp4'
        with open(lst, 'w') as f:
            for s in segs:
                f.write(f"file '{os.path.abspath(s['file'])}'\n")
        ff('-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', out)
        files.append(out)
    lens = [dur(f) for f in files]
    inputs = []
    fc = []
    chain = lens[0]
    v, a = '[0:v]', '[0:a]'
    for f in files:
        inputs += ['-i', f]
    for i in range(1, len(files)):
        off = chain - ctx.xf
        fc.append(f'{v}[{i}:v]xfade=transition=fade:duration={ctx.xf}:offset={off:.3f}[v{i}]')
        fc.append(f'{a}[{i}:a]acrossfade=d={ctx.xf}:c1=tri:c2=tri[a{i}]')
        v, a = f'[v{i}]', f'[a{i}]'
        chain = off + lens[i]
    fc.append(f'{v}fade=t=in:d=0.6,fade=t=out:st={chain - 0.8:.3f}:d=0.8,format=yuv420p[vout]')
    fc.append(f'{a}anull[aout]')
    ff(*inputs, '-filter_complex', ';'.join(fc), '-map', '[vout]', '-map', '[aout]', *venc(ctx.fps), *AENC, '-movflags', '+faststart', 'cut.mp4')
    print(f'cut.mp4 expected {chain:.2f}s, actual {dur("cut.mp4"):.2f}s')


def final(ctx, name, ass, music):
    T = dur('cut.mp4')
    inputs = ['-i', 'cut.mp4']
    if music:
        inputs += ['-stream_loop', '-1', '-i', music['path']]
        fc = (f"[1:a]volume={music.get('volume', 0.17)},atrim=0:{T:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=2,afade=t=out:st={T-4.5:.3f}:d=4.5[m0];"
              f"[0:a]asplit[v1][v2];[m0][v2]sidechaincompress=threshold=0.015:ratio=8:attack=30:release=600:makeup=1[md];"
              f"[v1][md]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.89:level=false[a];")
    else:
        fc = '[0:a]anull[a];'
    fc += f'[0:v]ass={ass}[v]'
    ff(*inputs, '-filter_complex', fc, '-map', '[v]', '-map', '[a]', '-t', f'{T:.3f}',
       '-c:v', 'libx264', '-crf', '18', '-preset', 'slow', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
       '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', name)
    print('wrote', name, dur(name), flush=True)
