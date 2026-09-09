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
| `sources` | list of `{path}` | required | one clip in phase 2a; `start`/`end` trims and several clips arrive in phase 2b |
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

## video

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `width` | int, 320..7680 | `1920` | master pixel width |
| `height` | int, 320..4320 | `1080` | master pixel height |
| `fps` | int, 10..120 | `30` | constant frame rate every later stage assumes |
| `chrome_top` | int, 0..1000 | `0` | rows of browser chrome to crop off the top of the source |
| `strip` | object | `{}` | see `video.strip` below |

### video.strip

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `mode` | `crop` \| `pad` \| `none` | `crop` | see "Strip modes" in the design spec |
| `height` | int, 0..1000 | `chrome_top` in `crop` mode, else `round(64 * height / 1080)` | strip height in master pixels; in `crop` mode it must equal `video.chrome_top` |
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
| `fonts` | `{bold, regular}` | see Notes | absolute font file paths; each falls back to the macOS Arial faces when empty or absent |

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
