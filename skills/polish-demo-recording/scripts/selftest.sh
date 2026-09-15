#!/usr/bin/env bash
# Self-test for the polish-demo-recording pipeline on a synthetic fixture (no recording, no ASR).
# usage: selftest.sh [--golden capture|check] [--keep] [--no-variants]
#   --golden capture  store timeline.json, the ASS files, the .srt and the ffmpeg argv log under fixture/golden-v1/
#   --golden check    diff the same five files against fixture/golden-v1/ (dev-machine parity gate; not for CI)
#   --keep            leave fixture/.work/ in place for inspection
#   --no-variants     skip the multi/voice-file/no-voice variants (golden + transcribe/probe checks only)
# Structural asserts run in every mode: expected cut length, A/V duration match, voice loudness,
# ASS event counts, .srt cue count, verify.png present. Exit 1 on the first failure.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/fixture"
WORK="$FIX/.work"
GOLD="$FIX/golden-v1"
golden=""
keep=0
VARIANTS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --golden) golden="$2"; shift 2;;
    --keep) keep=1; shift;;
    --no-variants) VARIANTS=0; shift;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
for t in ffmpeg ffprobe uv python3; do
  command -v "$t" >/dev/null || { echo "selftest: $t not installed" >&2; exit 1; }
done
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fonts: Arial on macOS, DejaVu Sans on Linux, fc-match as a last resort (absent on macOS).
resolve_font() {  # $1 = bold|regular
  local mac_b="/System/Library/Fonts/Supplemental/Arial Bold.ttf" mac_r="/System/Library/Fonts/Supplemental/Arial.ttf"
  local dv_b="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" dv_r="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
  if [ "$1" = bold ]; then
    [ -f "$mac_b" ] && { echo "$mac_b"; return; }
    [ -f "$dv_b" ] && { echo "$dv_b"; return; }
    command -v fc-match >/dev/null && fc-match -f '%{file}' 'sans-serif:bold' && return
  else
    [ -f "$mac_r" ] && { echo "$mac_r"; return; }
    [ -f "$dv_r" ] && { echo "$dv_r"; return; }
    command -v fc-match >/dev/null && fc-match -f '%{file}' 'sans-serif' && return
  fi
  fail "no usable font found for $1"
}
FONT_B="$(resolve_font bold)"
FONT_R="$(resolve_font regular)"

rm -rf "$WORK"
mkdir -p "$WORK"
bash "$FIX/make-fixture.sh" "$WORK"
cp "$FIX/whisper.json" "$WORK/whisper.json"

# In golden mode every ffmpeg call is logged through a PATH shim before exec of the real binary.
# Identical argv implies identical output regardless of encoder nondeterminism.
if [ -n "$golden" ]; then
  REAL_FFMPEG="$(command -v ffmpeg)"
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/ffmpeg" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/ffmpeg-calls.log"
exec "$REAL_FFMPEG" "\$@"
EOF
  chmod +x "$WORK/bin/ffmpeg"
  export PATH="$WORK/bin:$PATH"
fi

# probe.sh is not run: it seeks 30 s for its chrome frame and the fixture is 24 s, so under set -e it would abort.
cp "$WORK/fixture.mp4" "$WORK/src.mov"
bash "$HERE/voice-chain.sh" "$WORK/src.mov" "$WORK/voice.wav" 2> "$WORK/voice.txt"

python3 - "$FIX/plan-v2.json" "$WORK/plan.json" "$WORK/music.wav" <<'PY'
import json, sys
src, dst, music = sys.argv[1:]
plan = json.load(open(src))
plan['music']['path'] = music
json.dump(plan, open(dst, 'w'), indent=1)
PY

# A v1-shaped plan (positional ops) must be refused with pointed messages, before any ffmpeg call.
cat > "$WORK/bad.json" <<'JSON'
{"raw": "src.mov", "brand": {"name": "x"}, "src_start": 0.2, "src_end": 23.8,
 "speedups": [[15.0, 20.0, 4, true]], "zooms": [[5.6, 8.9, 1.25, 960, 540]], "callouts": [[1.0, "Single sign-on"]]}
JSON
if uv run --with "pillow>=10" "$HERE/build_demo.py" "$WORK/bad.json" gaps 2> "$WORK/bad.txt"; then fail "v1 plan was accepted"; fi
for msg in 'schema_version: must be 2' 'raw: unknown key' 'speedups\[0\]: must be an object' 'zooms\[0\]: must be an object' 'range: required'; do
  grep -q "$msg" "$WORK/bad.txt" || fail "validation message missing ($msg): $(cat "$WORK/bad.txt")"
done
grep -q Traceback "$WORK/bad.txt" && fail "validation crashed instead of reporting"
# An overlap must be caught by validation, not by the timeline assert after the master was rendered.
python3 - "$WORK/plan.json" "$WORK/overlap.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p['zooms'].append({'from': 15.8, 'to': 17.0, 'factor': 1.2, 'cx': 960, 'cy': 540})  # inside the speed-up window 15.5..19.6
json.dump(p, open(sys.argv[2], 'w'))
PY
if uv run --with "pillow>=10" "$HERE/build_demo.py" "$WORK/overlap.json" gaps 2> "$WORK/overlap.txt"; then fail "overlapping ops were accepted"; fi
grep -q 'zooms\[1\]: overlaps speedups\[0\]' "$WORK/overlap.txt" || fail "overlap message missing: $(cat "$WORK/overlap.txt")"
# Wrong field types must be reported as rules, not as a crash in the timeline arithmetic.
python3 - "$WORK/plan.json" "$WORK/types.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p['chapters'] = [{'cut': 'later', 'title': 7}]
p['labels'] = [{'at': '3', 'text': 'x'}]
p['zooms'] = [{'from': 5.6, 'to': 8.9, 'factor': 1.25, 'cx': '960', 'cy': 540}]
p['callouts'] = [{'at': 1.0, 'text': 'x', 'dur': 'long'}]
p['redactions'] = [{'from': 1, 'to': 2, 'x': 'left', 'y': 0, 'w': 50, 'h': 50}]
p['captions'] = None
p['timing'] = 'fast'
p['workdir'] = None
p['music']['path'] = False
p['video']['width'] = 321
p['brand']['accent'] = 'red'
p['brand']['fonts'] = 'Arial'
p['brand']['tiles'] = ['x']
json.dump(p, open(sys.argv[2], 'w'))
PY
if uv run --with "pillow>=10" "$HERE/build_demo.py" "$WORK/types.json" gaps 2> "$WORK/types.txt"; then fail "wrong field types were accepted"; fi
for msg in 'chapters\[0\].cut: must be a number' 'chapters\[0\].title: must be a string' 'labels\[0\].at: must be a number' 'zooms\[0\].cx: must be a number' 'callouts\[0\].dur: must be a number' 'redactions\[0\].x: must be a number' 'captions: must be an object' 'timing: must be an object' 'plan.workdir: must be a string' 'music.path: must be a path string' 'video.width: must be an even integer' 'brand.accent: must be a hex colour' 'brand.fonts: must be' 'brand.tiles\[0\]: must be'; do
  grep -q "$msg" "$WORK/types.txt" || fail "type message missing ($msg): $(cat "$WORK/types.txt")"
done
grep -q Traceback "$WORK/types.txt" && fail "type validation crashed instead of reporting"
# A speed-up shorter than its 0.5 s + 0.4 s edge guards would invert and duplicate source; validation must refuse it.
python3 - "$WORK/plan.json" "$WORK/short.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p['speedups'] = [{'from': 15.0, 'to': 15.9, 'factor': 4}]
json.dump(p, open(sys.argv[2], 'w'))
PY
if uv run --with "pillow>=10" "$HERE/build_demo.py" "$WORK/short.json" gaps 2> "$WORK/short.txt"; then fail "a 0.9 s speed-up was accepted"; fi
grep -q 'speedups\[0\]: must span more than 0.95 s' "$WORK/short.txt" || fail "short speed-up message missing: $(cat "$WORK/short.txt")"

cd "$WORK"
BUILD="uv run --with pillow>=10 $HERE/build_demo.py"
$BUILD plan.json gaps > gaps.txt
$BUILD plan.json > build.txt  # every stage, verify included

# ---- structural asserts
python3 - "$WORK" <<'PY'
import json, os, re, subprocess, sys
work = sys.argv[1]
os.chdir(work)
def dur(path, stream):
    out = subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', stream, '-show_entries', 'stream=duration', '-of', 'default=nw=1:nk=1', path])
    return float(out.strip())
def lufs(path):
    err = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', path, '-af', 'ebur128', '-f', 'null', '-'], capture_output=True, text=True).stderr
    return float(re.search(r'^\s+I:\s+(-?[\d.]+) LUFS', err, re.M).group(1))
def count(path, style):
    return sum(1 for l in open(path) if l.startswith('Dialogue:') and l.split(',')[3] == style)
fails = []
def check(cond, msg):
    if not cond:
        fails.append(msg)
cut = dur('cut.mp4', 'v:0')
check(abs(cut - 27.025) <= 0.15, f'cut.mp4 length {cut:.3f}, expected 27.025 +/- 0.15')
for name in ['fixture-polished.mp4', 'fixture-polished-no-music.mp4', 'fixture-polished-captions.mp4']:
    check(os.path.exists(name), f'{name} missing')
    if os.path.exists(name):
        check(abs(dur(name, 'v:0') - dur(name, 'a:0')) <= 0.05, f'{name}: video and audio durations differ by more than 50 ms')
voice = lufs('voice.wav')
check(abs(voice + 16.0) <= 1.5, f'voice.wav integrated loudness {voice}, expected -16 +/- 1.5')
check(re.search(r'^loudness: I -?[\d.]+ LUFS, target -16 \(ok\)', open('build.txt').read(), re.M) is not None, 'verify: loudness line missing or off target')
check(re.search(r'^streams: video [\d.]+s, audio [\d.]+s, within 50 ms', open('build.txt').read(), re.M) is not None, 'verify: A/V duration line missing or over 50 ms')
check(count('overlays.ass', 'Hdr') == 2, 'overlays.ass: expected 2 Hdr events (one per source run)')
check(count('overlays.ass', 'LT') == 2, 'overlays.ass: expected 2 LT events (two callouts)')
check(count('overlays.ass', 'Badge') == 1, 'overlays.ass: expected 1 Badge event (one fast-forward)')
check(count('overlays_cc.ass', 'Cap') == 4, 'overlays_cc.ass: expected 4 Cap events (four narration bursts)')
srt = open('fixture-polished.srt').read().strip().split('\n\n')
check(len(srt) == 4, f'srt: expected 4 cues, got {len(srt)}')
check(os.path.getsize('verify.png') > 0, 'verify.png missing or empty')
tl = json.load(open('timeline.json'))
check(len(tl) == 9, f'timeline: expected 9 segments, got {len(tl)}')
if fails:
    print('\n'.join('FAIL: ' + f for f in fails))
    sys.exit(1)
print('structural asserts: ok')
PY

# Strip modes: the master filter for each mode, checked as strings (the fixture only renders crop).
uv run --with "pillow>=10" python3 - "$HERE" <<'PY'
import copy, json, sys
from PIL import Image
sys.path.insert(0, sys.argv[1])
from demo import plan, render
base = json.load(open('plan.json'))
def vf(mode, chrome_top, height=64):
    p = copy.deepcopy(base)
    p['video']['chrome_top'] = chrome_top
    p['video']['strip'] = {'mode': mode, 'height': height, 'color': '0b1220'}
    if mode == 'crop':
        p['video']['strip']['height'] = chrome_top
    return render.master_vf(plan.build(p, '.'))
want = {
    ('crop', 64): 'fps=30,crop=1920:1016:0:64,pad=1920:1080:0:64:color=0x0b1220,format=yuv420p',
    ('crop', 0): 'fps=30,format=yuv420p',
    ('pad', 0): 'fps=30,scale=1920:1016:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:64:color=0x0b1220,format=yuv420p',
    ('none', 0): 'fps=30,format=yuv420p',
    ('none', 64): 'fps=30,crop=1920:1016:0:64,scale=1920:1080,format=yuv420p',
}
for (mode, ct), exp in want.items():
    got = vf(mode, ct)
    assert got == exp, f'{mode} chrome_top={ct}:\n  got  {got}\n  want {exp}'
print('strip modes: ok')

p = copy.deepcopy(base)
p['redactions'] = [{'from': 1, 'to': 4, 'x': 100, 'y': 200, 'w': 301, 'h': 80},
                   {'from': 5, 'to': 6, 'x': 10, 'y': 10, 'w': 50, 'h': 20, 'mode': 'box'}]
got = render.master_vf(plan.build(p, '.'))
exp = ("fps=30,crop=1920:1016:0:64,pad=1920:1080:0:64:color=0x0b1220"
       ",split[m0][r0];[r0]crop=300:80:100:200,avgblur=sizeX=20:sizeY=20[b0];[m0][b0]overlay=x=100:y=200:enable='between(t,1.000,4.000)'"
       ",drawbox=x=10:y=10:w=50:h=20:color=0x0b1220:t=fill:enable='between(t,5.000,6.000)',format=yuv420p")
assert got == exp, f'redactions:\n  got  {got}\n  want {exp}'
bad = copy.deepcopy(base)
bad['redactions'] = [{'from': 1, 'to': 4, 'x': 1900, 'y': 0, 'w': 100, 'h': 10}]
errs = plan.validate(bad, '.')
assert any('lies outside' in x for x in errs), errs
print('redactions: ok')

logo_plan = copy.deepcopy(base)
logo_plan['brand']['logo'] = 'logo.png'
Image.new('RGBA', (200, 60), (255, 0, 0, 255)).save('logo.png')
ctx = plan.build(logo_plan, '.')
assert ctx.logo_w == 160, f'logo_w: got {ctx.logo_w}, want 160'
got = render.master_vf(ctx)
want_tail = '[m],movie=logo.png,scale=-1:48[lg];[m][lg]overlay=x=40:y=8,format=yuv420p'
assert got.endswith(want_tail), f'master_vf with logo:\n  got  {got}\n  want ...{want_tail}'

# Card text fits the frame width: a 16:9 frame keeps the designed size, a 540x960 portrait frame shrinks the hero title.
land = plan.build(copy.deepcopy(base), '.')
assert render.fit(land, 'Acme Console', land.fb, 180, render.sx(land, 146)).size == render.fs(land, 180), 'fit shrank a 16:9 hero title'
port_plan = copy.deepcopy(base)
port_plan['video'] = {'width': 540, 'height': 960, 'chrome_top': 0, 'strip': {'mode': 'pad', 'height': 48}}
port = plan.build(port_plan, '.')
f = render.fit(port, 'Acme Console', port.fb, 180, render.sx(port, 146))
assert f.size < render.fs(port, 180), 'fit did not shrink the hero title on a portrait frame'
assert render.sx(port, 146) + f.getlength('Acme Console') <= 540 - int(540 * render.CARD_MARGIN), f'portrait hero title still clips at {f.size} px'
print('card fit: ok')

dark_plan = copy.deepcopy(base)
dark_plan['brand']['theme'] = 'dark'
dark_ctx = plan.build(dark_plan, '.')
assert dark_ctx.bg == (11, 18, 32), f'dark bg: got {dark_ctx.bg}'
assert dark_ctx.tile_bg == (17, 26, 46), f'dark tile_bg: got {dark_ctx.tile_bg}'
print('logo + theme: ok')
PY

# ---- golden capture / check (paths normalised so the files carry no machine-specific prefix)
norm() { sed -e "s#$WORK#<WORK>#g" -e "s#$(dirname "$FONT_B")#<FONTS>#g" "$1"; }
files="timeline.json overlays.ass overlays_cc.ass fixture-polished.srt ffmpeg-calls.log"
if [ "$golden" = capture ]; then
  mkdir -p "$GOLD"
  for f in $files; do norm "$WORK/$f" > "$GOLD/$f"; done
  echo "golden: captured $files -> $GOLD"
elif [ "$golden" = check ]; then
  for f in $files; do
    diff -u "$GOLD/$f" <(norm "$WORK/$f") || fail "golden diff in $f"
  done
  echo "golden: identical"
fi

# transcribe.sh and probe.sh checks go here, after the golden section: probe.sh's ffmpeg calls
# would otherwise land in ffmpeg-calls.log through the shim. Task 4's variants follow this block.
# transcribe.sh: the command per backend, printed, never run.
t="$HERE/transcribe.sh"
out=$(bash "$t" audio16k.wav whisper --backend faster --language de --print)
grep -q 'backend=faster language=de' <<<"$out" || fail "transcribe faster: $out"
grep -q 'faster-whisper' <<<"$out" || fail "transcribe faster command: $out"
out=$(bash "$t" audio16k.wav whisper --backend mlx --language de --print)
grep -q 'mlx_whisper' <<<"$out" && grep -q -- '--language de' <<<"$out" || fail "transcribe mlx: $out"
out=$(bash "$t" audio16k.wav whisper --backend none)
grep -q 'backend none' <<<"$out" || fail "transcribe none: $out"
# probe.sh on the 24 s fixture: the frame seek must land inside the clip.
mkdir -p "$WORK/probe"
bash "$HERE/probe.sh" "$WORK/fixture.mp4" "$WORK/probe" > "$WORK/probe/out.txt" 2>&1 || fail "probe.sh failed: $(tail -5 "$WORK/probe/out.txt")"
grep -q 'pixel_scale: 1' "$WORK/probe/out.txt" || fail "probe: pixel_scale line missing"
[ -s "$WORK/probe/frame30.png" ] && [ -s "$WORK/probe/chrome-top.png" ] || fail "probe: frames missing"
# No audio stream (a voice: "none" recording): the audio analyses are skipped, the frames still come out.
mkdir -p "$WORK/probe-noaudio"
bash "$HERE/probe.sh" "$WORK/noaudio.mp4" "$WORK/probe-noaudio" > "$WORK/probe-noaudio/out.txt" 2>&1 || fail "probe.sh failed on a silent-video file: $(tail -5 "$WORK/probe-noaudio/out.txt")"
grep -q '== audio: none' "$WORK/probe-noaudio/out.txt" || fail "probe: no-audio line missing"
[ -s "$WORK/probe-noaudio/montage.png" ] && [ -s "$WORK/probe-noaudio/chrome-top.png" ] || fail "probe: frames missing for the no-audio file"
# A continuous tone has no silence over 1.5 s; "none found" is a result, not a failure.
mkdir -p "$WORK/probe-tone"
bash "$HERE/probe.sh" "$WORK/tone12.mp4" "$WORK/probe-tone" > "$WORK/probe-tone/out.txt" 2>&1 || fail "probe.sh failed on a clip without silences: $(tail -5 "$WORK/probe-tone/out.txt")"
grep -q '== silences' "$WORK/probe-tone/out.txt" && grep -q 'pixel_scale: 1' "$WORK/probe-tone/out.txt" || fail "probe: tone clip output incomplete"
grep -q 'start:' "$WORK/probe-tone/out.txt" && fail "probe: a silence was reported on a continuous tone"
echo "transcribe + probe: ok"

if [ "$VARIANTS" = 1 ]; then
  BUILD="uv run --with pillow>=10 $HERE/build_demo.py"
  variant() {  # $1 name, $2 python that edits plan dict `p`, $3 stages, $4 expected outputs (space-separated)
    local name="$1" edit="$2" stages="$3" expect="$4" v="$WORK/var-$1"
    mkdir -p "$v"
    ln -sf "$WORK/fixture.mp4" "$v/src.mov"
    ln -sf "$WORK/a.mp4" "$v/a.mp4"; ln -sf "$WORK/b.mp4" "$v/b.mp4"; ln -sf "$WORK/vo.wav" "$v/vo.wav"
    ln -sf "$WORK/vo-short.wav" "$v/vo-short.wav"
    ln -sf "$WORK/bumper.mp4" "$v/bumper.mp4"; ln -sf "$WORK/portrait.mp4" "$v/portrait.mp4"
    cp "$FIX/whisper.json" "$v/whisper.json"
    uv run --with pillow python3 -c "from PIL import Image; Image.new('RGBA', (200, 60), (255, 0, 0, 255)).save('$v/logo.png')"
    python3 - "$WORK/plan.json" "$v/plan.json" "$WORK/music.wav" <<PY
import json, sys
p = json.load(open(sys.argv[1]))
p['music']['path'] = sys.argv[3]
p['out_prefix'] = 'var-$name'
$edit
json.dump(p, open(sys.argv[2], 'w'), indent=1)
PY
    ( cd "$v"
      vin=$($BUILD plan.json prepare | sed -n 's/^voice input: //p')
      if [ -n "$vin" ]; then
        # "voice input: <file> [--offset x]"; voice-chain.sh binds <src> <out.wav> first, flags after.
        set -- $vin
        bash "$HERE/voice-chain.sh" "$1" voice.wav "${@:2}" 2> voice.txt
      fi
      $BUILD plan.json $stages > build.txt 2>&1 || { tail -20 build.txt; exit 1; }
      for f in $expect; do [ -s "$f" ] || { echo "missing $f"; exit 1; }; done
    ) || fail "variant $name"
  }
  variant multi "p['sources'] = [{'path': 'a.mp4'}, {'path': 'b.mp4'}]" "master cards segs concat ass" "cut.mp4 overlays.ass var-multi.srt"
  variant voice-file "p['voice'] = {'path': 'vo-short.wav', 'offset': -0.35}" "master cards segs concat ass" "cut.mp4 overlays_cc.ass"
  variant no-voice "p['voice'] = 'none'; p['transcript'] = None" "master cards segs concat ass final" "var-no-voice.mp4 var-no-voice-no-music.mp4"
  variant ops "p['cuts'] = [{'from': 20.5, 'to': 21.5}]; p['holds'] = [{'at': 2.0, 'dur': 1.0}]; p['redactions'] = [{'from': 1.0, 'to': 4.0, 'x': 100, 'y': 200, 'w': 300, 'h': 80}, {'from': 5.0, 'to': 6.0, 'x': 10, 'y': 10, 'w': 50, 'h': 20, 'mode': 'box'}, {'from': 20.0, 'to': 22.0, 'x': 400, 'y': 400, 'w': 100, 'h': 100}]; p['bumpers'] = {'intro': 'bumper.mp4'}; p['brand']['logo'] = 'logo.png'; p['brand']['theme'] = 'dark'; p['loudness'] = {'target': -23}" "master cards segs concat ass final verify" "cut.mp4 var-ops.mp4 verify.png"
  # Portrait 540x960: every verify cell must share one canvas or hstack refuses the mixed 640x1138 / 640x360 inputs.
  variant portrait "p['sources'] = [{'path': 'portrait.mp4'}]; p['video'] = {'width': 540, 'height': 960, 'chrome_top': 0, 'strip': {'mode': 'pad', 'height': 48}}; p['zooms'][0]['cx'] = 270; p['zooms'][0]['cy'] = 480" "" "var-portrait.mp4 verify.png"
  variant exports "p['loudness'] = {'target': -14}; p['chapters'][0]['title'] = 'Models = v2; #1'; p['exports'] = {'height': 720, 'preview': {'from': 3.0, 'to': 8.0}, 'formats': ['srt', 'vtt', 'txt', 'chapters']}" "master cards segs concat ass final" "var-exports.mp4 var-exports-720p.mp4 var-exports-preview.mp4 var-exports.vtt var-exports.txt var-exports-chapters.txt var-exports.srt"
  python3 - "$WORK" "$HERE/build_demo.py" <<'PY'
import json, os, re, subprocess, sys
work, build_py = sys.argv[1], sys.argv[2]
def dur(path):
    return float(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=duration', '-of', 'default=nw=1:nk=1', path]).strip())
def count(path, style):
    return sum(1 for l in open(path) if l.startswith('Dialogue:') and l.split(',')[3] == style)
fails = []
for name in ('multi', 'voice-file', 'no-voice'):
    v = os.path.join(work, 'var-' + name)
    cut = dur(os.path.join(v, 'cut.mp4'))
    if abs(cut - 27.025) > 0.15:
        fails.append(f'{name}: cut.mp4 {cut:.3f}, expected 27.025 +/- 0.15')
    tl = json.load(open(os.path.join(v, 'timeline.json')))
    if len(tl) != 9:
        fails.append(f'{name}: {len(tl)} segments, expected 9')
    if count(os.path.join(v, 'overlays.ass'), 'Hdr') != 2:
        fails.append(f'{name}: expected 2 Hdr events')
if count(os.path.join(work, 'var-multi', 'overlays_cc.ass'), 'Cap') != 4:
    fails.append('multi: expected 4 Cap events')
if count(os.path.join(work, 'var-voice-file', 'overlays_cc.ass'), 'Cap') != 4:
    fails.append('voice-file: expected 4 Cap events')
if os.path.exists(os.path.join(work, 'var-no-voice', 'var-no-voice-captions.mp4')) or os.path.exists(os.path.join(work, 'var-no-voice', 'var-no-voice.srt')):
    fails.append('no-voice: a captions variant or an srt was written without a transcript')
v = os.path.join(work, 'var-ops')
cut = dur(os.path.join(v, 'cut.mp4'))
if abs(cut - 27.575) > 0.15:
    fails.append(f'ops: cut.mp4 {cut:.3f}, expected 27.575 +/- 0.15')
tl = json.load(open(os.path.join(v, 'timeline.json')))
if len(tl) != 13 or sum(1 for s in tl if s.get('hold')) != 1 or sum(1 for s in tl if s['kind'] == 'bumper') != 1:
    fails.append(f'ops: timeline shape wrong: {len(tl)} segments, holds {sum(1 for s in tl if s.get("hold"))}, bumpers {sum(1 for s in tl if s["kind"] == "bumper")}')
if count(os.path.join(v, 'overlays.ass'), 'Hdr') != 2:
    fails.append('ops: expected 2 Hdr events')
log = open(os.path.join(v, 'build.txt')).read()
# The third redaction (20-22 s) straddles the cut (20.5-21.5): its midpoint is cut away but the region is on screen
# either side, so verify must still show it. 16 cells: 3 cards, 2 callouts, 1 badge, 1 hold, 1 bumper, 3 redactions,
# 3 dissolves, 1 zoom pair.
m = re.search(r'verify\.png: (\d+) frames', log)
if not m or int(m.group(1)) != 16:
    fails.append(f'ops: verify.png has {m.group(1) if m else "?"} frames, expected 16 (the redaction straddling the cut must keep a cell)')
if 'warning: redaction' in log:
    fails.append('ops: a redaction was reported as entirely inside a cut, but 20-22 s is only partly cut')
if 'warning: callout' in log:
    fails.append('ops: a callout was dropped, but no callout sits inside the cut (TimeMap regression)')
if 'warning: caption' in log:
    fails.append('ops: a caption was dropped, but no cue starts inside the cut')
gaps = subprocess.run(['uv', 'run', '--with', 'pillow>=10', build_py, 'plan.json', 'gaps'], cwd=os.path.join(work, 'var-multi'), capture_output=True, text=True).stdout
if 'clip boundary' not in gaps:
    fails.append('multi: gaps did not print the clip boundary')
# voice-file: the 0.35 s lead-in must be gone, so the first burst starts at 0.5 s like the embedded voice.
err = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', os.path.join(work, 'var-voice-file', 'voice.wav'), '-af', 'silencedetect=n=-35dB:d=0.3', '-f', 'null', '-'], capture_output=True, text=True).stderr
m = re.search(r'silence_end: ([\d.]+)', err)
if not m or abs(float(m.group(1)) - 0.5) > 0.1:
    fails.append(f'voice-file: first silence_end {m.group(1) if m else "missing"}, expected 0.50 +/- 0.10')
# voice-file: the track ends 4 s before the video; the master mux pads it, so the video keeps its full length.
v = os.path.join(work, 'var-voice-file')
def dur_a(path):
    return float(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'a:0', '-show_entries', 'stream=duration', '-of', 'default=nw=1:nk=1', path]).strip())
mv, ma = dur(os.path.join(v, 'master.mov')), dur_a(os.path.join(v, 'master.mov'))
if abs(mv - 24.0) > 0.1 or abs(ma - mv) > 0.05:
    fails.append(f'voice-file: master.mov video {mv:.2f}s, audio {ma:.2f}s; expected both 24.0 (short voice padded, video not truncated)')
if 'clamped to' in open(os.path.join(v, 'build.txt')).read():
    fails.append('voice-file: src_end was clamped to a master shortened by the voice track')
# ops: bumpers follow the plan's loudness target (-23 here), like the narration.
def lufs(path):
    err = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', path, '-af', 'ebur128', '-f', 'null', '-'], capture_output=True, text=True).stderr
    return float(re.search(r'^\s+I:\s+(-?[\d.]+) LUFS', err, re.M).group(1))
v = os.path.join(work, 'var-ops')
for name, want in (('voice.wav', -23.0), (os.path.join('bumper', 'intro.mov'), -23.0)):
    got = lufs(os.path.join(v, name))
    if abs(got - want) > 1.5:
        fails.append(f'ops: {name} at {got} LUFS, expected {want} +/- 1.5')
# voice-offset.py must recover the fixture's known offset from the two files.
out = subprocess.run(['uv', 'run', '--with', 'numpy', os.path.join(os.path.dirname(build_py), 'voice-offset.py'), os.path.join(work, 'fixture.mp4'), os.path.join(work, 'vo.wav')], capture_output=True, text=True).stdout
m = re.search(r'offset: (-?[\d.]+)', out)
if not m or abs(float(m.group(1)) + 0.35) > 0.02:
    fails.append(f'voice-offset.py: {out.strip()!r}, expected offset: -0.350 +/- 0.02')
# A track that starts late (positive offset) with a --window whose matching sound lies before the window in track time
# (reference 12..14 s is track 10..12 s). A one-sided search from 12 s in track time has no overlap with it at all.
out = subprocess.run(['uv', 'run', '--with', 'numpy', os.path.join(os.path.dirname(build_py), 'voice-offset.py'), os.path.join(work, 'noise-ref.wav'), os.path.join(work, 'noise-late.wav'), '--window', '12:14'], capture_output=True, text=True).stdout
m = re.search(r'offset: (-?[\d.]+)', out)
if not m or abs(float(m.group(1)) - 2.0) > 0.02:
    fails.append(f'voice-offset.py --window 12:14 on a late track: {out.strip()!r}, expected offset: 2.000 +/- 0.02')
v = os.path.join(work, 'var-portrait')
def probe_wh(path):
    return subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', path]).decode().strip()
if probe_wh(os.path.join(v, 'var-portrait.mp4')) != '540,960':
    fails.append(f'portrait: output is {probe_wh(os.path.join(v, "var-portrait.mp4"))}, expected 540,960')
if probe_wh(os.path.join(v, 'verify', '00.png')) != '640,1138':
    fails.append(f'portrait: verify cell is {probe_wh(os.path.join(v, "verify", "00.png"))}, expected 640,1138 (one canvas in the frame aspect)')
v = os.path.join(work, 'var-exports')
def probe_h(path):
    return int(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=height', '-of', 'default=nw=1:nk=1', path]).strip())
if probe_h(os.path.join(v, 'var-exports-720p.mp4')) != 720:
    fails.append('exports: 720p copy is not 720 px tall')
pv = dur(os.path.join(v, 'var-exports-preview.mp4'))
if abs(pv - 5.0) > 0.1:
    fails.append(f'exports: preview {pv:.2f}s, expected 5.0')
vtt = open(os.path.join(v, 'var-exports.vtt')).read()
if not vtt.startswith('WEBVTT') or vtt.count(' --> ') != 4:
    fails.append('exports: vtt header or cue count wrong')
txt = open(os.path.join(v, 'var-exports.txt')).read().strip().splitlines()
if len(txt) != 4 or not txt[0].startswith('[00:03] Welcome'):
    fails.append(f'exports: txt lines {txt[:2]}')
ch = open(os.path.join(v, 'var-exports-chapters.txt')).read().splitlines()
if len(ch) != 2 or not ch[0].startswith('00:00 Acme Console') or not ch[1].endswith(' Models = v2; #1'):
    fails.append(f'exports: chapter list {ch}')
chapters = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_chapters', '-of', 'json', os.path.join(v, 'var-exports.mp4')]))['chapters']
titles = [c.get('tags', {}).get('title') for c in chapters]
if titles != ['Acme Console', 'Models = v2; #1']:
    fails.append(f'exports: mp4 chapter titles {titles} (FFMETADATA escaping of = ; #)')
# loudness target -14 on the voice chain
err = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', os.path.join(v, 'voice.wav'), '-af', 'ebur128', '-f', 'null', '-'], capture_output=True, text=True).stderr
lufs = float(re.search(r'^\s+I:\s+(-?[\d.]+) LUFS', err, re.M).group(1))
if abs(lufs + 14.0) > 1.5:
    fails.append(f'exports: voice.wav at {lufs} LUFS, expected -14 +/- 1.5')
if fails:
    print('\n'.join('FAIL: ' + f for f in fails))
    sys.exit(1)
print('variants: ok')
PY
fi

cd "$HERE"
[ "$keep" = 1 ] || rm -rf "$WORK"
echo "selftest: pass"
