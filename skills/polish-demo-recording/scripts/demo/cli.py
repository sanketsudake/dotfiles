"""Build a polished demo video from a JSON edit plan. Run with: uv run --with "pillow>=10" build_demo.py <plan.json> [stages...]

Stages (default: all): master cards segs concat ass final verify gaps prepare
  gaps    - print the narration gaps from the whisper JSON with a suggested treatment (card / speedup), then exit
  prepare - normalize and join the clips; print the file voice-chain.sh should read
  master  - crop the browser chrome, pad a branded strip back, constant fps; mux the processed voice WAV
  cards   - render title, chapter and end cards (Pillow)
  segs    - cut every timeline segment from the master (speed-ups, eased zooms) with identical encode settings
  concat  - join runs with -c copy, then one xfade/acrossfade chain across every card boundary
  ass     - lower-thirds, header labels, fast-forward badges, optional captions, .srt sidecar (time-mapped)
  final   - overlays + optional sidechain-ducked music, three variants (music / no music / captions)
  verify  - stream durations, loudness, and verify.png: direct-seek frames at every card, callout, badge and zoom
See ../references/ffmpeg-recipes.md for why each parameter is what it is.
"""
import json
import sys
from demo import overlays, plan, render, sources, timeline, verify

DEFAULT_STAGES = ['master', 'cards', 'segs', 'concat', 'ass', 'final']


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv:
        # v1 did sys.exit(__doc__): usage on stderr, exit status 1.
        print(__doc__, file=sys.stderr)
        return 1
    ctx = plan.load(argv[0])
    stages = argv[1:] or DEFAULT_STAGES
    if 'gaps' in stages:
        overlays.gaps(ctx, sources.boundaries(ctx))
        return 0
    if 'prepare' in stages:
        path = sources.prepare(ctx)
        offset = f' --offset {ctx.voice_offset:g}' if ctx.voice_offset else ''
        if ctx.voice_mode == 'embedded':
            print(f'voice input: {path}')
        elif ctx.voice_mode == 'file':
            print(f'voice input: {ctx.voice_path}{offset}')
        else:
            print('voice: none (skip voice-chain.sh and transcription)')
        return 0
    if 'master' in stages:
        render.master(ctx)
    if 'cards' in stages:
        render.make_cards(ctx)
        print('cards ok')
    tl = timeline.build_timeline(ctx)
    total = render.render_segs(ctx, tl, 'segs' in stages)
    print(f'timeline: {len(tl)} segments, {total:.1f}s (with dissolves)')
    json.dump(tl, open('timeline.json', 'w'), indent=1)
    if 'concat' in stages:
        render.concat(ctx, tl)
    tm = timeline.TimeMap(tl)
    if 'ass' in stages:
        open('overlays.ass', 'w').write(overlays.build_ass(ctx, tl, tm))
        open('overlays_cc.ass', 'w').write(overlays.build_ass(ctx, tl, tm, captions=True))
        overlays.write_srt(ctx, tm)
        print('overlays + srt ok')
    if 'final' in stages:
        music = ctx.music
        if music:
            render.final(ctx, f'{ctx.out}.mp4', 'overlays.ass', music)
            render.final(ctx, f'{ctx.out}-captions.mp4', 'overlays_cc.ass', music)
            render.final(ctx, f'{ctx.out}-no-music.mp4', 'overlays.ass', None)
        else:
            render.final(ctx, f'{ctx.out}.mp4', 'overlays.ass', None)
            render.final(ctx, f'{ctx.out}-captions.mp4', 'overlays_cc.ass', None)
    if 'verify' in stages:
        verify.verify(ctx, tl, tm)
    return 0
