---
name: polish-demo-recording
description: >-
  Turns a raw narrated screen recording (macOS screen capture, Slack or Loom
  export, any VFR .mov/.mp4 with the presenter's own voice) into a customer-ready
  product demo with ffmpeg only: measured audio clean-up and loudness, browser
  chrome replaced by a branded strip, chapter cards placed in real pauses,
  fast-forwarded waits, eased zooms, lower-third callouts, a ducked music bed,
  captions and an .srt. Use when the user says "beautify / polish / clean up
  this recording", "make this demo presentable", "remove the noise from my
  voice", "add title cards and music", "the video flickers at the transitions",
  or hands over a screen recording to share with a customer. Not for generating
  narration (the presenter records it) or for cutting a teaser from finished footage.
license: Apache-2.0
compatibility: "ffmpeg 6+, ffprobe, uv; macOS or Linux (transcription: mlx-whisper on Apple Silicon, faster-whisper elsewhere); fonts: Arial, DejaVu Sans, Liberation Sans, or brand.fonts"
metadata:
  author: sanketsudake
  version: "2.0"
---

# Polish a demo recording

The presenter records the flow in their own voice;
this skill does the editing.
Every choice is measured, not eyeballed, because the agent cannot watch or listen:
loudness in LUFS, noise floor in dB RMS, gaps from word timestamps, frames by direct seeks.
The original file is never modified; deliverables are new files next to it.

Scripts live in `{baseDir}/scripts/`; the reasoning behind each ffmpeg parameter is in `{baseDir}/references/ffmpeg-recipes.md`.
Read that file before changing a filter value.

## Inputs to ask for, or assume

- The recording path. macOS names carry U+202F (narrow no-break space) before "PM", so a typed path does not match; pass it from a glob. `probe.sh` refuses a missing path and copies the file to `src.mov` so nothing downstream has to quote it.
- Product name, one-line tagline, footer (company), accent colour. Default to what the UI shows.
- Music: a track the user supplies, or none. Never generate narration with TTS; synthetic voices read as robotic and get rejected.
- Output name. Default `<name>-polished.mp4` beside the original, plus `-no-music`, `-captions` and `.srt`.
  `exports` can add a downscaled copy for chat, a preview clip, `.vtt`/`.txt` transcripts, a YouTube chapter list, and chapters inside the mp4.
  The loudness target follows the destination: `-14` YouTube, `-16` default, `-23` broadcast.
- Several clips go in `sources` in order and are joined before anything else; `build_demo.py plan.json prepare` prints the file the voice chain reads.
- A voice track recorded separately goes in `voice: {path, offset}`, and `offset` is measured with `uv run --with numpy {baseDir}/scripts/voice-offset.py <src> <track.wav> --window a:b`, never guessed.
- A recording with no narration takes `voice: "none"` and gets no captions and no ducking.

## Workflow

Work in a scratch directory; keep `plan.json`, `timeline.json`, `overlays*.ass` and `voice.wav` so a revision is a re-render, not a redo.

### 1. Measure the source

```bash
{baseDir}/scripts/probe.sh "<raw>" <workdir>
```

Read the output and the three PNGs it writes.
Decide from numbers:

| Reading | Meaning | Action |
| --- | --- | --- |
| `r_frame_rate=300/1` or similar | variable frame rate | the `master` stage forces 30 fps; never cut the raw file directly |
| L minus R is `-inf` | dual mono mic | the voice chain collapses to mono |
| noise floor vs speech RMS gap < 25 dB | audible hiss or room tone | keep the default denoiser (`--nr 12 --nlm 2`) |
| `chrome-top.png` shows tabs and an address bar | browser chrome in frame | measure its height in px (64 on Chrome/Helium at 1080p) and set `chrome_top` and `video.strip.mode: crop`; a terminal or IDE recording with no chrome takes `strip.mode: pad` to keep the header, or `none` |
| silences > 4 s | waiting on the UI | fast-forward candidates, not cuts |
| `== audio: none` | the recording has no audio stream | set `voice` to `"none"`, or record the narration separately and use `voice: {path, offset}` |
| `pixel_scale: 2` | a 2x Retina capture | `video.width/height` still default to the source's native size, so pixels stay 1:1; set them smaller only to downscale on purpose |

### 2. Transcribe with word timestamps

```bash
ffmpeg -i src.mov -vn -ac 1 -ar 16000 audio16k.wav
{baseDir}/scripts/transcribe.sh audio16k.wav whisper [--language xx]
```

`transcribe.sh` picks `mlx-whisper` on Apple Silicon macOS and `faster-whisper` elsewhere (`--backend` overrides), both writing the same word-timestamp JSON shape; omit `--language` to auto-detect.
Whisper gives clean sentences and word times but drops most "uh"s;
the `transcribe` skill (parakeet) hears fillers but only in 15 s chunks.
Use whisper for placement and captions, parakeet only to count fillers.

### 3. Process the voice

```bash
{baseDir}/scripts/voice-chain.sh <src> voice.wav [--target -14|-16|-23] [--offset s] [--window a:b] [--dip a:b]
```

The script prints the result loudness (target I per `--target`, default −16 LUFS; TP −1.5 dBFS) and the speech RMS.
`--target` picks the loudness preset: `-14` for YouTube and streaming, `-16` for podcast (the default), `-23` for EBU R128 broadcast; true peak stays −1.5 dBFS for every target.
Confirm the floor moved: measure a 0.6 s silent core of a gap before and after with `astats`, not the whole whisper gap; breath and consonant edges are broadband, survive the denoiser, and read louder after make-up gain.
A passing vehicle or a bump is a low rumble below 600 Hz;
locate it with `showspectrumpic` on the window and hand the window to `--window` (steep high-pass and extra denoise only there), plus `--dip` on a silent gap that still carries it.
Do not pitch-shift; EQ and compression make the voice fuller without artefacts.

### 4. Write the edit plan

```bash
cp {baseDir}/assets/example-plan.json plan.json          # then set sources, range, video, brand; every key is in references/plan-schema.md
uv run --with "pillow>=10" {baseDir}/scripts/build_demo.py plan.json gaps   # narration gaps with a suggested treatment
```

The template names files that do not exist yet (`src.mov`, the transcript, the music track); the build refuses with one line per missing file until they are filled in.

Fill the rest of `plan.json` from the gap list and the transcript:

- **Chapters** (`chapters`) only where the narration changes topic *and* there is a pause; `cut` at gap start + 0.2 s, `resume` at gap end − 0.5 s. Two to three seconds per card; six cards is plenty for seven minutes. A short or densely narrated clip may offer one usable pause or none: one card or zero is the right answer, never a card inside speech.
- **Speed-ups** (`speedups {from, to, factor, badge}`) for every gap > 2.4 s where the screen is loading or the presenter is waiting: ×3, or ×4 with a badge when > 4 s. Fast-forward beats a hard cut because the motion stays continuous.
- **Zooms** (`zooms {from, to, factor, cx, cy}`) at ≤ 1.3× on two to four high-value moments (a code dialog, a response, a budget field). Check the frame at the zoom start first so the target is already on screen.
- **Callouts** (`callouts {at, text}`) are value statements, one per feature, ≤ 60 characters, timed to the word that introduces the feature.
- **Labels** (`labels {at, text}`) change the header strip's chapter name without a card.
- **Caption fixes** (`caption_fixes {find, replace}`) for product names the recognizer mangled.
- **Cuts** remove a range hard.
  Use one for a wrong page or a notification, never for an "uh": the jump cut reads as broken on a screen recording.
  A card or speed-up inside a cut is refused; a callout or a caption that starts inside one is dropped with a warning.
  A cue that started before the cut keeps its words on screen until the cut start.
- **Holds** freeze the frame while the narration continues:
  for a result the presenter talks over while the screen keeps scrolling.
- **Redactions** box a region in master pixels for a window (opaque by default; `blur` only for cosmetic masking, since a blur can be read back);
  measure the box on a direct-seek frame.
  They live in the master, so a re-plan never moves them.
- **Bumpers** are intro and outro clips normalized to the frame and level-matched to the plan's loudness target.
  A changed bumper file keeps its old render until `bumper/` is deleted, like `norm/`.
- **Logo** replaces the product name on chapter and end cards, joins the hero name on the open card, and sits in the strip.
- **Theme** `dark` swaps the card palette; `accent` stays.
- **Card text fits the width**: the layout is designed at 16:9, so on a portrait frame each card title, tagline, blurb, tile and end line is shrunk until it fits between its left edge and a 4 % right margin; 16:9 frames keep the designed sizes.

### 5. Build

```bash
uv run --with "pillow>=10" {baseDir}/scripts/build_demo.py plan.json           # all stages
uv run --with "pillow>=10" {baseDir}/scripts/build_demo.py plan.json ass final # after editing only overlays or music
```

Stages: `master` (crop chrome, pad the strip, 30 fps, mux voice) → `cards` → `segs` → `concat` (runs joined with `-c copy`, then one xfade/acrossfade chain across card boundaries, fade from and to black) → `ass` → `final` → `verify`.
Delete `seg/NNN.mp4` for a segment whose source range changed; unchanged segments are reused.

### 6. Verify before delivering

`verify` prints the stream durations and flags a video/audio difference over 50 ms with a `warning:` prefix, prints integrated loudness and true peak, and writes `verify.png`: direct-seek frames at every card, callout, badge, hold, bumper, zoom, dissolve and redaction (the middle of the longest part of it still on screen, so a cut that removes its midpoint does not hide it from the sheet).
The redacted region must be unreadable in the frame at the window's midpoint.
The loudness line names the plan's target and flags a difference over 1 LU with a `warning:` prefix, not a failure.
Read the image.
Zooms at ≤ 1.3× are subtle by design, so each zoom gets a before/after pair cropped 1:1 around the target; judge the zoom on that pair, not on the full frame.
Reject the build if any callout is clipped, a header label sits on a card, a zoom pair shows the wrong region, or the strip is missing.
When a music bed is used, measure it on its own: render the ducked stem alone and check about −21 LUFS on cards and −30 to −41 LUFS under speech (see the recipes file).

### 7. Deliver

Copy the variants next to the original with the name the user asked for, hand the main file to the user in the conversation, and tell the user what to listen for, because you could only measure:
sibilance from the de-esser, a gated feel between words, music breathing in pauses, thinness in any `--window` region.
Exports the plan asked for land beside it by suffix: a downscaled `-<height>p.mp4`, a `-preview.mp4` clip, `.vtt` and `.txt` transcripts, and a `-chapters.txt` list for YouTube.
The same chapter marks are also muxed into every final mp4 variant that exists (main, `-captions`, `-no-music`).

## Common mistakes

- Cutting the raw VFR file: A/V drift and xfade misalignment. Always build from the normalized master.
- Timing overlays against source seconds after cutting: every callout drifts. `TimeMap` in `demo/timeline.py` maps source → output time, including the dissolve overlaps.
- `select=eq(n,…)` contact sheets on the concatenated output come out time-shifted. Verify with direct `-ss` seeks only.
- `afftdn` alone: gaps sit at −31 dB after make-up gain. `anlmdn` after it is what keeps them low.
- Zooming the whole frame: the branded strip stretches. `zoom_vf` crops the strip off, zooms the content and pads it back.
- A zoompan on a text card at 30 fps shimmers and reads as flicker. Cards are static; dissolves supply the motion.
- `WrapStyle: 2` (needed so lower-thirds never wrap) also disables caption wrapping: captions are pre-broken into lines by measured pixel width, each within `captions.max_width_frac` (default `0.8`) of the frame width.
- Shell traps on macOS: `sed -i ''` fails under GNU sed from nix; `$VAR:l` in a zsh string lowercases the variable; BSD `grep -E` does not know `\s`. Put ffmpeg chains in a script file.
- Auto-removing "uh"s at word boundaries: on a screen recording the jump cuts look broken. Cut only stutters and fillers that sit in pauses; offer a voice-only re-record of weak chapters instead.
- Guessing `voice.offset`: even 100 ms reads as bad lip sync on a screen recording; measure it.

## Quick reference

| Task | Where |
| --- | --- |
| Measure a raw file | `{baseDir}/scripts/probe.sh` |
| Clean and normalize the voice | `{baseDir}/scripts/voice-chain.sh` |
| Plan, build, verify | `{baseDir}/scripts/build_demo.py <plan.json> [stages]` |
| Example plan | `{baseDir}/assets/example-plan.json` |
| Every plan key, default and phase | `{baseDir}/references/plan-schema.md` |
| Why each parameter | `{baseDir}/references/ffmpeg-recipes.md` |
| Self-test on a synthetic clip (no recording, no ASR) | `{baseDir}/scripts/selftest.sh` |
