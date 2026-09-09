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
| `callouts` | list of objects | `[]` | see [Operations](#operations-chapters-labels-speedups-zooms-callouts-caption_fixes) |
| `callout_dur` | number, seconds | `5.0` | default duration for a callout that carries no `dur` |
| `caption_fixes` | list of `{find, replace}` | `[]` | regex substitutions applied to caption text, before the built-in "uh" clean-up |
| `captions` | object | `{}` | see [captions](#captions-music-timing) |
| `music` | `{path, volume}` or null | null | background bed, sidechain-ducked under narration |
| `timing` | object | `{}` | see [timing](#captions-music-timing) |
| `out_prefix` | string | required | `<out_prefix>.mp4`, `-no-music`, `-captions`, `.srt` |

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
| `width` | int, 320..7680 | the first clip's native size (from ffprobe) | master pixel width |
| `height` | int, 320..4320 | the first clip's native size (from ffprobe) | master pixel height |
| `fps` | int, 10..120 | `30` | constant frame rate every later stage assumes |
| `chrome_top` | int, 0..1000 | `0` | rows of browser chrome to crop off the top of the source |
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
| `name` | string | required | shown in the header strip and on every card |
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

## range

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `start` | number, seconds | required | first master second the timeline covers |
| `end` | number, seconds | required | last master second the timeline covers; must be greater than `start` |

## Operations (chapters, labels, speedups, zooms, callouts, caption_fixes)

All times below are master seconds and must lie inside `range`.
`chapters`, `speedups` and `zooms` share one axis of non-overlapping windows;
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
| `to` | number, seconds | required | master second it ends; must be greater than `from` |
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
| `xfade` | number, 0.1..30 | `0.45` | dissolve duration between pieces, seconds |
