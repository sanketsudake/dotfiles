#!/usr/bin/env bash
# Self-test for the polish-demo-recording pipeline on a synthetic fixture (no recording, no ASR).
# usage: selftest.sh [--golden capture|check] [--keep]
#   --golden capture  store timeline.json, the ASS files, the .srt and the ffmpeg argv log under fixture/golden-v1/
#   --golden check    diff the same five files against fixture/golden-v1/ (dev-machine parity gate; not for CI)
#   --keep            leave fixture/.work/ in place for inspection
# Structural asserts run in every mode: expected cut length, A/V duration match, voice loudness,
# ASS event counts, .srt cue count, verify.png present. Exit 1 on the first failure.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/fixture"
WORK="$FIX/.work"
GOLD="$FIX/golden-v1"
golden=""
keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --golden) golden="$2"; shift 2;;
    --keep) keep=1; shift;;
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

python3 - "$FIX/plan-v1.json" "$WORK/plan.json" "$FONT_B" "$FONT_R" "$WORK/music.wav" <<'PY'
import json, sys
src, dst, fb, fr, music = sys.argv[1:]
plan = json.load(open(src))
plan['brand']['font_bold'] = fb
plan['brand']['font_regular'] = fr
plan['music']['path'] = music
json.dump(plan, open(dst, 'w'), indent=1)
PY

cd "$WORK"
BUILD="uv run --with pillow>=10 $HERE/build_demo.py"
$BUILD plan.json gaps > gaps.txt
$BUILD plan.json > build.txt
$BUILD plan.json verify > verify.txt

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

cd "$HERE"
[ "$keep" = 1 ] || rm -rf "$WORK"
echo "selftest: pass"
