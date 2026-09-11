"""Everything before the master: probe a clip, normalize each clip to the frame (trim, fit, fps, audio as PCM),
join clips with -c copy, and hand the master stage and the voice chain one file to read.

A single clip that already matches the frame and has no trims is used as it is, so the phase 1 goldens hold."""
import json
import os
import subprocess
from demo.ffmpeg import dur, ff


def probe(path):
    """Width, height, frame rate, duration and whether an audio stream exists, from ffprobe."""
    out = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type,width,height,r_frame_rate:format=duration', '-of', 'json', path])
    d = json.loads(out)
    video = next(s for s in d['streams'] if s.get('codec_type') == 'video')
    num, den = video['r_frame_rate'].split('/')
    return {
        'width': int(video['width']),
        'height': int(video['height']),
        'fps': float(num) / float(den or 1),
        'duration': float(d['format']['duration']),
        'has_audio': any(s.get('codec_type') == 'audio' for s in d['streams']),
    }


def fit_vf(ctx):
    """Scale a clip into the frame with its aspect kept, letterboxed with the strip colour."""
    return f'scale={ctx.W}:{ctx.H}:force_original_aspect_ratio=decrease,pad={ctx.W}:{ctx.H}:(ow-iw)/2:(oh-ih)/2:color=0x{ctx.strip_color}'


def _needs_work(ctx):
    if len(ctx.sources) > 1:
        return True
    s = ctx.sources[0]
    if 'start' in s or 'end' in s:
        return True
    info = probe(s['path'])
    return (info['width'], info['height']) != (ctx.W, ctx.H)


def normalize_clip(ctx, path, out, seek=(), loudnorm=False):
    """Encode one clip into the master format: fit into the frame, master fps, PCM stereo audio (silence when the clip has none)."""
    info = probe(path)
    inputs = [*seek, '-i', path]
    maps = []
    if not info['has_audio']:
        inputs += ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo']
        maps = ['-map', '0:v', '-map', '1:a', '-shortest']
    af = ['-af', f'loudnorm=I={ctx.loudness_target:g}:TP=-1.5'] if (loudnorm and info['has_audio']) else []
    vf = f'fps={ctx.fps},{fit_vf(ctx)},format=yuv420p'
    ff(*inputs, *maps, '-vf', vf, *af, '-c:v', 'libx264', '-crf', '15', '-preset', 'fast', '-pix_fmt', 'yuv420p',
       '-c:a', 'pcm_s16le', '-ar', '48000', '-ac', '2', out)
    return info


def bumper(ctx, which):
    """Normalize bumpers.<which> into bumper/<which>.mov, level-matched to loudness.target; None when not set."""
    path = ctx.bumpers.get(which)
    if not path:
        return None
    os.makedirs('bumper', exist_ok=True)
    out = f'bumper/{which}.mov'
    if not os.path.exists(out):
        normalize_clip(ctx, path, out, loudnorm=True)
    return out


def prepare(ctx):
    """Return the path the master encodes from. One matching untrimmed clip: the clip itself. Otherwise norm/joined.mov."""
    if not _needs_work(ctx):
        return ctx.sources[0]['path']
    os.makedirs('norm', exist_ok=True)
    parts = []
    for i, s in enumerate(ctx.sources):
        out = f'norm/{i:02d}.mov'
        parts.append(out)
        if os.path.exists(out):
            continue
        seek = []
        if 'start' in s:
            seek += ['-ss', f"{float(s['start']):.3f}"]
        if 'end' in s:
            seek += ['-t', f"{float(s['end']) - float(s.get('start', 0.0)):.3f}"]
        info = normalize_clip(ctx, s['path'], out, seek=seek)
        print(f'{out} from {s["path"]} ({info["width"]}x{info["height"]}, {dur(out):.2f}s)', flush=True)
    lst = 'norm/joined.txt'
    if not os.path.exists('norm/joined.mov'):
        with open(lst, 'w') as f:
            for p in parts:
                f.write(f"file '{os.path.abspath(p)}'\n")
        ff('-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', 'norm/joined.mov')
    return 'norm/joined.mov'


def boundaries(ctx):
    """Master seconds at which each clip after the first starts (from the normalized parts); empty for one clip.

    Normalizes the clips first when needed, so `gaps` works before `prepare` has run."""
    if len(ctx.sources) < 2:
        return []
    prepare(ctx)
    t = 0.0
    out = []
    for i in range(len(ctx.sources) - 1):
        t += dur(f'norm/{i:02d}.mov')
        out.append(round(t, 3))
    return out
