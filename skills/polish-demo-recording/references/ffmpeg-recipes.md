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
- `pad` mode (no chrome to crop): `fps=30,scale=1920:1016:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:64:color=0x0b1220,format=yuv420p` — the content is scaled by `(H − strip) / H`, a few percent, to make room for a strip under a recording that had no browser chrome to begin with.
- `none` mode: `fps=30,crop=1920:1016:0:64,scale=1920:1080,format=yuv420p` when there is chrome to crop, else just `fps=30,format=yuv420p` — no strip and no header events are emitted.

## Voice chain (`voice-chain.sh`)

| Stage | Setting | Why |
| --- | --- | --- |
| `pan=mono` | collapse dual mono | halves the noise work, no imaging to lose |
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

## Segments

- Identical encode settings for every segment so runs can be joined with `-c copy`: `-r 30 -c:v libx264 -crf 16 -preset medium -pix_fmt yuv420p -video_track_timescale 30000 -c:a aac -b:a 192k -ar 48000 -ac 2`.
- Accurate cut: `-ss <a> -t <d> -i master.mov` (input seeking decodes from the previous keyframe and discards).
- Speed-up: `setpts=PTS/s` and `atempo=s,volume=0` (silence; the denoised room tone sped up adds nothing).
- Cards: `-loop 1 -framerate 30 -t D -i card.png` with anullsrc audio. Static: a slow zoompan on fine text shimmers.

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
- Captions: cues pre-broken to two lines of ≤ 42 characters, `\N` between lines, `BorderStyle=3` box, lower-thirds raised to y = H−280 in the captioned variant so they do not collide.

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

## Self-test fixture

`scripts/fixture/make-fixture.sh` renders 24 s of `testsrc2` with a synthetic narration:
a 220 Hz tone under 4 Hz amplitude modulation, gated into four bursts so the transcript in `fixture/whisper.json` has three real gaps (1.5, 3 and 5 s).
The voice chain lands it at −16.0 LUFS (measured); the assert allows ±1.5 LU.
`selftest.sh --golden check` diffs the timeline, both ASS files, the .srt and the ffmpeg argv log against `fixture/golden-v1/`; identical argv means identical output, so encoder nondeterminism never enters the comparison.
