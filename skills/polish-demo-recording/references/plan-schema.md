# plan.json schema (v2)

Every time is in **master seconds**: the time axis of `master.mov` after normalization,
before any cut, card or speed-up.
Pixels (`cx`, `cy`) are master pixels.
Keys not listed here are refused (`<key>: unknown key`).

## Top level

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `schema_version` | int | required | must be `2` |
| `workdir` | path | plan's directory | every relative path resolves here |
| `sources` | list of objects | required | one clip or several, joined in order; see [sources](#sources) |
| `voice` | `"embedded"` \| `"none"` \| `{path, offset}` | `"embedded"` | `embedded`: `voice-chain.sh` reads the master's own audio (v1 behaviour). `none`: no narration; captions and ducking are skipped, but the `gaps` stage still runs and prints clip boundaries only. `{path, offset}`: a separately recorded track; `offset` (seconds, negative when the track starts early) is measured, never guessed — see `voice-offset.py` in `ffmpeg-recipes.md` |
| `voice_wav` | path | `voice.wav` | output of `voice-chain.sh` |
| `transcript` | path or null | null | word-timestamp JSON (`segments[].words[] {start, end, word}`) |
| `video` | object | `{}` | see [video](#video) |
| `brand` | object | required | see [brand](#brand) |
| `range` | `{start, end}` | required | the master window the timeline covers |
| `first_label` | string | `Welcome` | header label before the first chapter |
| `chapters` | list of objects | `[]` | see [Operations](#operations-chapters-labels-speedups-zooms-callouts-caption_fixes) |
| `labels` | list of objects | `[]` | see [Operations](#operations-chapters-labels-speedups-zooms-callouts-caption_fixes) |
| `speedups` | list of objects | `[]` | see [Operations](#operations-chapters-labels-speedups-zooms-callouts-caption_fixes) |
| `zooms` | list of objects | `[]` | see [Operations](#operations-chapters-labels-speedups-zooms-callouts-caption_fixes) |
| `cuts` | list of objects | `[]` | phase 3; see [Operations](#operations-chapters-labels-speedups-zooms-callouts-caption_fixes) |
| `holds` | list of objects | `[]` | phase 3; see [Operations](#operations-chapters-labels-speedups-zooms-callouts-caption_fixes) |
| `callouts` | list of objects | `[]` | see [Operations](#operations-chapters-labels-speedups-zooms-callouts-caption_fixes) |
| `callout_dur` | number, seconds | `5.0` | default duration for a callout that carries no `dur` |
| `caption_fixes` | list of `{find, replace}` | `[]` | regex substitutions applied to caption text, before the built-in "uh" clean-up |
| `captions` | object | `{}` | see [captions](#captions-music-timing) |
| `music` | `{path, volume}` or null | null | background bed, sidechain-ducked under narration |
| `timing` | object | `{}` | see [timing](#captions-music-timing) |
| `redactions` | list of objects | `[]` | phase 3; box (or blur) a region for a window, in master time; see [redactions](#redactions) |
| `bumpers` | `{intro, outro}` | `{}` | phase 3; intro and outro clips; see [bumpers](#bumpers) |
| `loudness` | `{target}` | `{}` | phase 4; integrated loudness target for `voice-chain.sh`; see [loudness](#loudness) |
| `exports` | object | `{}` | phase 4; extra deliverables next to the final mix; see [exports](#exports) |
| `out_prefix` | string | required | `<out_prefix>.mp4`, `-no-music`, `-captions`, `.srt`; refused when any derived output, or a fixed intermediate (`master.mov`, `cut.mp4`, `voice.wav`, …), resolves to an input file, because every render runs `ffmpeg -y` |

## sources

Each entry is a clip; entries are normalized (trim, fit to `video.width × video.height`, `fps`) and joined in order with `-c copy`.
One clip that already matches the frame and carries no `start`/`end` is used as it is, so the phase 1 goldens hold.

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `path` | path | required | clip file |
| `start` | number, seconds | clip start | trims the clip; seconds within that clip, not master seconds |
| `end` | number, seconds | clip end | trims the clip; must be greater than `start` when both are given |

## video

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `width` | even int, 320..7680 | the first clip's native size (from ffprobe), rounded down to even | master pixel width; libx264 with yuv420p refuses an odd frame, so an explicit odd value is a validation error |
| `height` | even int, 320..4320 | the first clip's native size (from ffprobe), rounded down to even | master pixel height; same rule |
| `fps` | int, 10..120 | `30` | constant frame rate every later stage assumes |
| `chrome_top` | int, 0..1000 | `0` | rows of browser chrome to crop off the top of the source; must leave at least 16 px of content in the frame (explicit or probed height), like `strip.height` in `pad` mode |
| `strip` | object | `{}` | see `video.strip` below |

### video.strip

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `mode` | `crop` \| `pad` \| `none` | `crop` | `crop`: crop the chrome and pad the same height back, UI pixels stay 1:1 (v1). `pad`: scale the content down to make room for a strip under a recording with no chrome. `none`: no strip, no header events. See "Strip modes" in the design spec |
| `height` | int, 0..1000 | `chrome_top` in `crop` mode; `round(64 * height / 1080)` in `pad` mode; `0` in `none` mode | strip height in master pixels; in `crop` mode it must equal `video.chrome_top` (the strip replaces the chrome, so the content stays 1:1 — ffmpeg's `pad` would refuse any other height) |
| `color` | hex string, no `#` | `0b1220` | strip background color |

## brand

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `name` | string | required | shown in the header strip and on every card. Every `brand` key below is type-checked by `validate()`: strings, `#rrggbb` colours, `tiles` as `[title, subtitle]` pairs, `end_lines` as strings, `fonts` as an object |
| `subtitle` | string | `Product demo` | opening-card subtitle |
| `accent` | hex color | `#3b5bfd` | header, chapter numerals, tile stripe |
| `ink` | hex color | `#0b1220` | primary text |
| `muted` | hex color | `#788296` | secondary text |
| `card_bg` | hex color | `#f8fafc` | card background |
| `light` | hex color | `#d5d9e2` | chapter-numeral background tint |
| `tagline` | string | none | opening-card tagline |
| `blurb` | string | none | opening-card blurb |
| `tiles` | list of `[title, subtitle]` | `[]` | opening-card feature tiles |
| `footer` | string | none | footer text on the open and end cards |
| `end_title` | string | `Thank you` | end-card heading |
| `end_lines` | list of strings | `[]` | end-card body lines |
| `fonts` | `{bold, regular}` | see Notes | absolute font file paths; when empty or absent, `resolve()` tries this override, then Arial (macOS), then DejaVu Sans, then Liberation Sans, reusing one matched face for both bold and regular when only one is given, and exits 2 with the tried list if none match |
| `logo` | path | none | phase 3; PNG. Every path field in the plan (`sources[].path`, `voice.path`, `transcript`, `music.path`, `bumpers.*`, this one) must be a string naming an existing file, reported as `<path>: must be a path string` otherwise. On chapter and end cards it replaces the small `brand.name` mark at the top left; on the open card it joins the hero `brand.name` text there instead of replacing it, because the hero text is the card's layout anchor. In the header strip it sits at the left edge at `strip.height − 16` px tall, only when a strip exists (`video.strip.mode` is not `none`) |
| `theme` | `light` \| `dark` | `light` | phase 3; sets the defaults of `ink`, `muted`, `card_bg`, `light`, `tile_bg` and `tile_outline`; an explicit value for any of those keys still wins over the theme. `accent` is not affected by `theme` |
| `tile_bg` | hex color | `#ffffff` (`light`) / `#111a2e` (`dark`) | phase 3; opening-card feature-tile background |
| `tile_outline` | hex color | `#e2e6ee` (`light`) / `#2a3650` (`dark`) | phase 3; opening-card feature-tile border |

## range

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `start` | number, seconds | required | first master second the timeline covers |
| `end` | number, seconds | required | last master second the timeline covers; must be greater than `start` |

## Operations (chapters, labels, speedups, zooms, callouts, caption_fixes)

All times below are master seconds and must lie inside `range`.
Every field is checked for type as well as presence:
a string where a number is due (`"cut": "later"`) is reported as `chapters[0].cut: must be a number`, not as a crash in the timeline.
`chapters`, `speedups`, `zooms`, `cuts` and `holds` share one axis of non-overlapping windows:
chapters `[cut, resume]`, speed-ups `[from + 0.5, to − 0.4]`, zooms `[from, to]`, cuts `[from, to]`, holds `[at, at + dur]`;
validation sorts them by start and rejects any pair that overlaps.

### chapters

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `cut` | number, seconds | required | master second where the source cuts to a chapter card |
| `resume` | number, seconds | `cut` | master second where the source resumes; must not be before `cut` |
| `title` | string | required | chapter-card heading |
| `subtitle` | string | none | chapter-card subheading |
| `label` | string | `title` | header-strip label shown after this chapter |

### labels

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `at` | number, seconds | required | master second the header-strip label changes |
| `text` | string | required | label text |

### speedups

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `from` | number, seconds | required | master second the fast section starts |
| `to` | number, seconds | required | master second it ends; must be more than 0.95 s after `from` (0.5 s of lead-in and 0.4 s of tail stay at normal speed, so a shorter span would invert the fast segment) |
| `factor` | number, 1.5..8 | required | playback speed multiplier; kept as the JSON value (`atempo`/`setpts` read it verbatim) |
| `badge` | bool | `false` | show the "Nx fast forward" badge |

### zooms

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `from` | number, seconds | required | master second the push-in starts |
| `to` | number, seconds | required | master second it ends; must be greater than `from` |
| `factor` | number, 1.0..2.0 | required | zoom multiplier at the peak |
| `cx` | int | required | zoom center x, master pixels |
| `cy` | int | required | zoom center y, master pixels |

### cuts

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `from` | number, seconds | required | master second the cut starts |
| `to` | number, seconds | required | master second it ends; must be greater than `from` |

Removes `[from, to]` hard: the timeline splits the run and the two neighbours join with `-c copy`.
A chapter card or speed-up may not sit inside a cut (validation error).
A callout or caption cue that starts inside a cut is dropped with a warning that names it;
a caption cue that starts before a cut and ends inside it is truncated to the cut start.
A header label whose time falls inside a cut is not dropped — it moves to the cut start, which is the label's visible effect anyway.

### holds

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `at` | number, seconds | required | master second the freeze starts |
| `dur` | number, seconds, 0.2..30 | required | how long the frame stays frozen; `at + dur` must lie inside `range` |

Freezes the frame at `at` for `dur` seconds while the narration keeps playing underneath; the source video for `[at, at + dur]` is not read again for playback, so speech and picture stay aligned.
No badge is shown.

### callouts

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `at` | number, seconds | required | master second the lower-third appears |
| `text` | string, max 60 chars | required | callout text |
| `dur` | number, seconds | `callout_dur` | how long the callout stays on screen |

### caption_fixes

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `find` | regex string | required | pattern applied to caption text |
| `replace` | string | required | replacement |

## redactions

Phase 3.
Applied at the master stage, in master pixels and master time, before any zoom — a zoom over a redacted region magnifies the box or blur, which is the intended result.
The default is an opaque `box`: a blur keeps low-frequency shape that a reader or OCR can recover from, so it is never the default for a secret;
ask for `blur` explicitly, and only for cosmetic masking of non-sensitive UI.
Redactions are not checked against `range` and do not share the chapters/speedups/zooms/cuts/holds overlap axis: a wrong region is fixed by re-running `master` and `segs`, not by re-planning.

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `from` | number, seconds | required | master second the redaction starts |
| `to` | number, seconds | required | master second it ends; must be greater than `from` |
| `x` | int, master pixels | required | left edge; must not be negative |
| `y` | int, master pixels | required | top edge; must not be negative |
| `w` | int, master pixels, ≥ 8 | required | width; below 8 px is refused |
| `h` | int, master pixels, ≥ 8 | required | height; below 8 px is refused |
| `mode` | `box` \| `blur` | `box` | `box`: `drawbox` filled with the strip colour, nothing of the region survives; `blur`: `avgblur=sizeX=20:sizeY=20` on the cropped region, cosmetic only, not for secrets |

`x + w` and `y + h` are checked against the frame only when `video.width` and `video.height` are both in the plan; otherwise the bounds check is skipped and an out-of-frame box is caught only visually, in `verify.png`.

## bumpers

Phase 3.
`bumpers` itself is `{}` or an object; each key is a path or `null`; any other key is refused.

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `intro` | path or null | none | clip placed before the open card, normalized to the master frame (see [sources](#sources)) and level-matched with `loudnorm` to `loudness.target`, joined with the same dissolve as a card |
| `outro` | path or null | none | clip placed after the end card, same treatment |

Cached at `bumper/<intro|outro>.mov`, keyed by the `bumpers` key name, not the file path;
a changed bumper file keeps its old render until `bumper/` is deleted, like `norm/`.

## loudness

Phase 4.

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `target` | `-14` \| `-16` \| `-23` | `-16` | integrated loudness target in LUFS, passed to `voice-chain.sh --target`; true peak stays `-1.5` dBFS for every target; `verify` flags a measured difference over 1 LU as a `warning:` line, not a failure |

## exports

Phase 4.
`exports` itself is `{}` or an object; any other key is refused.

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `height` | int, 240..2160, even | none | writes `<out_prefix>-<height>p.mp4`, the final mix downscaled with `scale=-2:<height>`; must be even because `yuv420p` needs an even frame height |
| `preview` | `{from, to}` in output seconds | none | writes `<out_prefix>-preview.mp4`, a straight `-ss`/`-t` cut of the final mix, for a chat message or a README |
| `formats` | list drawn from `srt`, `vtt`, `txt`, `chapters` | `["srt"]` | `srt` (v1) and `vtt`/`txt` need `transcript`; `chapters` writes `<out_prefix>-chapters.txt` (the `MM:SS Title` form YouTube reads) and mp4 chapter metadata muxed into every final variant that exists, timed from the timeline's card positions in output time |

## captions, music, timing

### captions

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `max_width_frac` | number, 0.3..1.0 | `0.8` | max caption line width as a fraction of frame width |

### music

`music` itself is `null` or an object.

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `path` | path | required when `music` is set | background track, looped for the render duration |
| `volume` | number, 0.0..1.0 | `0.17` | pre-sidechain gain, applied at render time |

### timing

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `card_dur` | number, 0.1..30 | `2.4` | chapter-card hold, seconds |
| `open_dur` | number, 0.1..30 | `3.2` | opening-card hold, seconds |
| `end_dur` | number, 0.1..30 | `5.0` | end-card hold, seconds |
| `xfade` | number, 0.1..30 | `0.45` | dissolve duration between pieces, seconds; `card_dur`, `open_dur` and `end_dur` must each be at least `2 × xfade` (a card dissolves in and out), and a source run or bumper shorter than `xfade` stops `concat` with a message naming it |
