# ffmpeg recipes and the measurements behind them

Measured on a 7-minute macOS screen recording of a web UI, 1080p, VFR declared 300 fps, AAC stereo (dual mono), voice at −28.8 LUFS with a −52 dB RMS floor.
Re-measure on a different source before trusting a number here.

## Master

```text
fps=30,crop=1920:1016:0:64,pad=1920:1080:0:64:color=0x0b1220,format=yuv420p   -c:v libx264 -crf 15 -preset fast
```

- Force constant frame rate first. Every later cut, xfade and concat assumes it.
- Crop the browser chrome and pad the same height back as a dark strip so UI pixels stay 1:1. Do not crop and upscale: a 1 Mbps screen recording is already soft.
- The strip carries the product name and the chapter label (ASS header events), which is why it is baked into the master.
- Mux the processed voice into the master so every segment takes video and audio from one file. That is the sync guarantee.
- The mux pads the voice with silence to the video length (`-af apad=whole_dur=<video length>`), so a track that ends early (a separate recorder, a negative offset trim) never shortens the master; `-shortest` only trims a track that runs past the video.
- `pad` mode (no chrome to crop): `fps=30,scale=1920:1016:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:64:color=0x0b1220,format=yuv420p` — the content is scaled by `(H − strip) / H`, a few percent, to make room for a strip under a recording that had no browser chrome to begin with.
- `none` mode: `fps=30,crop=1920:1016:0:64,scale=1920:1080,format=yuv420p` when there is chrome to crop, else just `fps=30,format=yuv420p` — no strip and no header events are emitted.
- Strip logo: `movie=<logo>,scale=-1:H[lg]` then `overlay=x=40:y=8` onto the strip, where `H` is `strip.height − 16` px (1080p values, scaled by `sx`/`sy` at other frame sizes) so a tall logo does not touch the strip edges.
  Only applied when a strip exists (`ctx.strip > 0`), so `video.strip.mode: none` gets card logos only, never a strip overlay.

## Redaction (`demo/render.py` `redact_vf`)

Appended to `master_vf` after the strip and logo filters, so a redaction is in master pixels and master time, like the rumble windows in the voice chain — it survives a re-plan.

```text
blur: split[m][r];[r]crop=w2:h2:x:y,avgblur=sizeX=20:sizeY=20[b];[m][b]overlay=x=x:y=y:enable='between(t,a,b)'
box:  drawbox=x=x:y=y:w=w:h=h:color=0x<strip_color>:t=fill:enable='between(t,a,b)'
```

- `avgblur=sizeX=20:sizeY=20`, not `boxblur=20:2`: `boxblur` refuses a radius of 20 on any region under 80 px in either direction, because its chroma planes are half-size, and a redaction box is often a single 30 px line of text.
`avgblur` carries no such radius-vs-size limit.
- The crop is rounded down to even sizes (`w - w % 2`, `h - h % 2`) before the blur: yuv420p chroma planes are half-resolution, and an odd crop size would misalign them against the luma plane.
- `box` is the default: it fills with the strip colour, so nothing of the region survives and it reads as intentional chrome, not a glitch.
`blur` is opt-in for cosmetic masking only; `avgblur` keeps low-frequency shape that a reader or OCR can recover from, so it is not a redaction of a secret.
- The region is measured in master pixels, before any zoom: a zoom over a redacted region magnifies the blur, which is the intended, not accidental, result.

## Normalize a clip (`demo/sources.py`)

```text
fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x0b1220,format=yuv420p
-c:v libx264 -crf 15 -preset fast -pix_fmt yuv420p -c:a pcm_s16le -ar 48000 -ac 2
```

- `fit_vf`: scale each source into `video.width × video.height` with its aspect kept, letterboxed with the strip colour, so a phone-shot clip and a desktop capture join into one frame without either being cropped.
- One matching, untrimmed clip skips this filter entirely and is used as it is (`prepare` returns the clip path itself) — that is what keeps the phase 1 goldens byte-identical.
- Audio becomes PCM (`pcm_s16le`), not AAC: the join in the next step uses `-c copy`, and `-c copy` on a concat demuxer list requires every part to share the exact same codec parameters.
PCM also has no encoder priming or delay, so the `-c copy` seam lands on an exact sample and the audio is encoded lossily only once, at the master, instead of twice.
A source with no audio stream gets `anullsrc` muxed in first so every part has an audio track to copy.
- Sources are then joined in order with the concat demuxer (`-f concat -safe 0`, `-c copy`) into `norm/joined.mov`, the file both the master stage and the voice chain read.

## Bumpers (`demo/sources.py` `bumper`)

An intro or outro clip goes through `normalize_clip` too, with `loudnorm=True`: single-pass `loudnorm=I=-16:TP=-1.5`, not the voice chain's two-pass measured run.
Single-pass loudnorm's error grows with the material's length and dynamic range; a 2 to 5 s bumper (a logo sting, a short music swell) has little of either, and it dissolves straight into a silent card, so a small residual miss in level is inaudible.
The voice chain keeps two-pass because narration runs minutes and needs the tighter number.
`bumper/<intro|outro>.mov` and `norm/*.mov` are both caches keyed by the `bumpers`/`sources` key, not by file content: swap the file at the same path and the old render is reused silently until the directory is deleted.

## Voice chain (`voice-chain.sh`)

| Stage | Setting | Why |
| --- | --- | --- |
| `aformat=channel_layouts=mono` | standard downmix, (L+R)/2 | halves the noise work, no imaging to lose; keeps narration that sits on one channel (`pan=mono|c0=c0` would drop the right channel) |
| `highpass=f=90` | | desk rumble, HVAC |
| `afftdn=nf=-48:nr=12:tn=1` | spectral denoise, tracking | main hiss removal |
| `anlmdn=s=2:p=0.002:r=0.006` | non-local means | without it, gaps sit at −31 dB after make-up gain; with it −46 dB |
| `deesser=i=0.25` | | compression brings up sibilance |
| `acompressor threshold −26 dB, 3:1, 5/120 ms, makeup 2` | | evens the read |
| EQ −2 dB @250 Hz, +2.5 dB @3.2 kHz, +1 dB @120 Hz | | less mud, more presence, a little body |
| `loudnorm I=-16 TP=-1.5 LRA=11`, two-pass with measured values, `linear=true` | | broadcast level; the two-pass keeps dynamics |
| `aresample=48000` | | loudnorm outputs 192 kHz otherwise |
| `alimiter=limit=0.89` | | −1 dBFS ceiling |

Result on the reference file: speech −31.5 → −18.5 dB RMS, gap −52 → −46 dB RMS, I −16.2 LUFS.
Measure gaps on a 0.6 s silent core: a window that includes breath or consonant edges reads worse after make-up gain (−38 → −25 dB on one clip) even though the hiss is gone.

Windowed rumble fix (a passing vehicle, 181–188 s):

```text
highpass=f=260:p=2:enable='between(t,181,188.5)' (twice = 24 dB/oct), lowshelf=f=400:g=-10:enable=…,
afftdn=nf=-40:nr=25:tn=1:enable=…, volume='1-0.85*clip(min(t-183.62,184.5-t)/0.08,0,1)':eval=frame
```

The 60–300 Hz band in the silent gap went −17 → −35 dB; speech formants above 300 Hz survive, the voice is slightly thinner for those seconds.
Find the band with `showspectrumpic=s=1400x500:legend=1:scale=log:stop=8000` on `atrim` of the window.

## Offset of a separate voice track (`voice-offset.py`)

```text
uv run --with numpy {baseDir}/scripts/voice-offset.py src.mov vo.wav --window 0:15
offset: -0.350
```

The two inputs are decoded to mono 16 kHz and cross-correlated by FFT; the lag of the peak is the offset, negative when the track starts early and positive when it starts late.
`--window a:b` narrows the reference to a span around a clap or the first word so a long recording locks on one event;
the track is searched over `a − 5 … b + 5`, so the matching sound is found on either side of the window in track time and offsets of either sign up to 5 s are measured.
The two decodes start at different origins (`a` and `a − 5`), and the script puts both back on the master axis before subtracting.
ffmpeg's `axcorrelate` is not usable here because it emits a correlation signal, not a lag.

## Segments

- Identical encode settings for every segment so runs can be joined with `-c copy`: `-r 30 -c:v libx264 -crf 16 -preset medium -pix_fmt yuv420p -video_track_timescale 30000 -c:a aac -b:a 192k -ar 48000 -ac 2`.
- Accurate cut: `-ss <a> -t <d> -i master.mov` (input seeking decodes from the previous keyframe and discards).
- Speed-up: `setpts=PTS/s` and `atempo=s,volume=0` (silence; the denoised room tone sped up adds nothing).
- Cards: `-loop 1 -framerate 30 -t D -i card.png` with anullsrc audio. Static: a slow zoompan on fine text shimmers.

## Hold

Two ffmpeg calls, not one filter: a direct-seek frame PNG at `at` (`-ss <at> -i master.mov -frames:v 1`), then that PNG looped for `dur` (`-loop 1 -framerate <fps> -t <dur> -i <png>`) muxed with the master's own audio for `[at, at + dur]` (`-ss <at> -t <dur> -i master.mov`, mapped `0:v` from the PNG and `1:a` from the master).
`render_segs` treats a hold as one source segment, so the video for `[at, at + dur]` is never read a second time for playback: the frozen frame and the narration underneath stay aligned with no separate skip step.
No badge: a hold is a narration device, not a fast-forward.

## Eased zoom on the content area only

```text
crop=W:H-STRIP:0:STRIP,
scale=w='trunc(W*Z/2)*2':h='trunc((H-STRIP)*Z/2)*2':eval=frame,
crop=W:H-STRIP:x='min(max(cx*Z-W/2,0),iw-W)':y='min(max((cy-STRIP)*Z-(H-STRIP)/2,0),ih-(H-STRIP))',
pad=W:H:0:STRIP:color=0x0b1220
Z = 1+(z-1)*E,  E = smoothstep(min(1,max(0,min(t/0.7,(D-t)/0.7))))
```

`scale` needs `eval=frame` to re-evaluate `t`; `crop` x/y are per-frame by default.
Keep z ≤ 1.3 on a 1080p screen capture.

## Concat with dissolves

Join consecutive source segments into runs with the concat demuxer (`-c copy`), then one chain:

```text
[0:v][1:v]xfade=transition=fade:duration=0.45:offset=O1[v1]; [v1][2:v]xfade=…:offset=O2[v2]; …
[0:a][1:a]acrossfade=d=0.45:c1=tri:c2=tri[a1]; …
offset_i = (chain length so far) − 0.45 ;  chain length after piece i = offset_i + len_i
```

Every transition shortens the output by the dissolve length; the output-time map subtracts one overlap per transition before any overlay is timed.
Then `fade=t=in:d=0.6` at the head and `fade=t=out` over the last 0.8 s.

## Overlays (one ASS file, libass)

- `PlayResX/Y` = frame size; `WrapStyle: 2` so lower-thirds never wrap.
- Lower-third box: a `\p1` rectangle whose width comes from Pillow measuring the text at 34 px Arial; accent bar 10 px; `\fad(250,250)`.
- Header: `\an4\pos(40,32)` product name, `\an6\pos(1880,32)` chapter label; events exist only during source runs, never on cards.
- Captions: cues pre-broken to lines by measured pixel width, each within `captions.max_width_frac` (default `0.8`) of the frame width, `\N` between lines, `BorderStyle=3` box, lower-thirds raised to y = H−280 in the captioned variant so they do not collide.

## Music bed

```text
[1:a]volume=V,atrim=0:T,afade in 2 s, afade out 4.5 s[m0]; [m0][voice]sidechaincompress=threshold=0.015:ratio=8:attack=30:release=600:makeup=1[md]; [voice][md]amix=normalize=0
```

Measure on the ducked stem alone (`-map "[md]" -vn`), never on the mix or by subtracting two AAC encodes:

| Track | V | on cards | under speech |
| --- | --- | --- | --- |
| generated ambient pad at −12.2 LUFS | 0.42 | −21.6 LUFS | −34 LUFS |
| corporate track at −11.6 LUFS, "very low" | 0.17 | −27 LUFS | −41 LUFS |

Start at the very low setting; a bed that is clearly audible under speech gets rejected as distracting.

## Final encode

`-c:v libx264 -crf 18 -preset slow -profile:v high -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 192k`.
Check: video and audio durations within 50 ms, I ≈ −16 LUFS, TP ≤ −1.5 dBFS.

## Verification that lies

`select='eq(n,N)'` after a filter on the xfade output returns frames in time order but shifted; contact sheets built that way put the wrong frame under the wrong label.
Use `-ss <t> -i final.mp4 -frames:v 1` per frame.

## Filler words

Typical counts for a 7-minute ad-lib read: "uh" about 30, sentence-initial "So" about 30, a handful of "yeah", two or three stutters.
Whisper dropped 30 of the 33 "uh"s, so it cannot drive automatic removal; a forced aligner (WhisperX) can.
Cut only stutters and fillers inside pauses; the rest needs a re-record.

## Chapters (`demo/exports.py` `write_chapters`, `mux_chapters`)

```text
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=180000
title=Acme Console
```

- The first mark is always `(0.0, brand.name)`; every chapter card after it adds a mark at its output-time position with the chapter's title.
- FFMETADATA values treat `=`, `;`, `#` and `\` as syntax (`#` and `;` start a comment, so an unescaped title is cut off there); `write_chapters` backslash-escapes them and flattens newlines, so a title like `Models = v2; #1` round-trips intact into the mp4.
- Muxed into every final variant that exists, with no re-encode: `-i <name> -i chapters.ffmeta -map_metadata 1 -map_chapters 1 -c copy -movflags +faststart`.
- `<out_prefix>-chapters.txt` carries the same marks as `MM:SS Title` lines, the form YouTube reads from a video description.
YouTube only renders chapters on the player from that list when there are at least three and each is 10 s or longer.
A two-card demo still gets the list file, just no chapters on the YouTube player.

## Downscale and preview (`demo/exports.py` `downscale`, `preview`)

```text
downscale: scale=-2:<height> -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -movflags +faststart -c:a copy
preview:   -ss <a> -t <b-a> -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 128k
```

- Both read the final mix (`<out_prefix>.mp4`), not the master, so overlays land in the downscale and the preview too.
Captions stay in the `-captions` variant only.
- The downscale copies the audio track (`-c:a copy`): only the video changes size, so there is no second lossy audio encode.
- The preview re-encodes video and audio through `-ss`/`-t` instead of `-c copy`, so its cut starts on an exact frame rather than the previous keyframe.

## Self-test fixture

`scripts/fixture/make-fixture.sh` renders 24 s of `testsrc2` with a synthetic narration:
a 220 Hz tone under 4 Hz amplitude modulation, gated into four bursts so the transcript in `fixture/whisper.json` has three real gaps (1.5, 3 and 5 s).
The voice chain lands it at −16.0 LUFS (measured); the assert allows ±1.5 LU.
`selftest.sh --golden check` diffs the timeline, both ASS files, the .srt and the ffmpeg argv log against `fixture/golden-v1/`; identical argv means identical output, so encoder nondeterminism never enters the comparison.

## Self-test variants

`make-fixture.sh` also renders `a.mp4`/`b.mp4` (the fixture split in half, each re-encoded on a keyframe), `vo.wav` (the fixture's voice track with 0.35 s of silence prepended, so its known offset is −0.35), `vo-short.wav` (the same track cut to 20.35 s), `noise-ref.wav`/`noise-late.wav` (seeded pink noise in the same bursts, and a copy with its first 2 s dropped, offset +2.0; noise because the tone repeats every 0.25 s and a different decoder can tip the correlation one AM cycle off), and two probe edge cases (`noaudio.mp4`, a 12 s continuous tone), at the same encode cost as the golden fixture — a few seconds of `libx264 veryfast`, no extra capture.
`selftest.sh`'s `variant()` helper builds each on a full pipeline run; no golden was captured for these paths in this phase, so structural asserts are the check, not a byte diff:

- `multi`: `sources` is `[a.mp4, b.mp4]`; proves `sources.prepare` joins several clips into one file the master and voice chain both read, and that `gaps` reports the clip boundary.
- `voice-file`: `voice` is `{path: vo-short.wav, offset: -0.35}`; proves `voice-chain.sh --offset` trims the track's known lead-in (checked with `silencedetect`: the first burst must land at 0.5 s, matching the embedded-voice fixture), that a voice track ending 4 s before the video is padded with silence in the master (`apad=whole_dur=<video length>`; `-shortest` only trims a longer track) instead of truncating the video, and that `voice-offset.py` recovers −0.35 s from `fixture.mp4` and `vo.wav` and +2.0 s from the `noise-ref.wav`/`noise-late.wav` pair with `--window 12:14` (the matching burst lies before the window in track time), so the measurement and the fix agree in both directions.
- `no-voice`: `voice` is `"none"` and `transcript` is `null`; proves no captions variant and no `.srt` are written, and that `final` still renders.
