#!/usr/bin/env bash
# Measure a raw screen recording before deciding any edit.
# usage: probe.sh <raw-video> <workdir>
# Copies the source to <workdir>/src.mov (macOS names carry U+202F before "PM", which breaks
# most shell quoting), then prints stream facts, loudness, noise floor, silences >1.5 s,
# and writes a frame montage plus a full-size frame for measuring browser chrome.
set -euo pipefail
raw="${1:?raw video}"; work="${2:?workdir}"
if [ ! -f "$raw" ]; then
  echo "not found: $raw" >&2
  echo "macOS names carry U+202F before PM; a typed space does not match. Pass the path from a glob, e.g. \"\$(ls ~/Documents/Screen*Recording*5.21*.mov)\"" >&2
  exit 1
fi
mkdir -p "$work"
# A reused work dir keeps its src.mov only while it is still this recording; otherwise it is replaced, so no
# measurement below can describe a previous input. The same-file case (raw is src.mov itself) copies nothing.
if [ -f "$work/src.mov" ] && [ "$raw" -ef "$work/src.mov" ]; then :
elif [ -f "$work/src.mov" ] && cmp -s "$raw" "$work/src.mov"; then :
else cp -f "$raw" "$work/src.mov"; fi
cd "$work"
echo "== streams"
ffprobe -v error -show_entries format=duration,size,bit_rate \
  -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels \
  -of default=nw=1 src.mov
# voice: "none" plans may carry a recording with no audio stream; every audio filter below would fail on it.
has_audio=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 src.mov | head -1)
if [ -z "$has_audio" ]; then
  echo "== audio: none (no audio stream; set voice to \"none\" in the plan, or add a separately recorded track)"
else
  echo "== loudness (target after processing: I -16 LUFS, TP -1.5 dBFS)"
  ffmpeg -hide_banner -nostats -i src.mov -af ebur128=peak=true -f null - 2>&1 | grep -E '^[[:space:]]+(I|LRA|Peak):'
  echo "== L minus R (-inf means dual mono: collapse to mono before processing)"
  ffmpeg -hide_banner -nostats -i src.mov -af "atrim=10:40,aeval=val(0)-val(1):c=mono,astats=measure_perchannel=none" -f null - 2>&1 | grep 'RMS level' || true
  echo "== noise floor, first 2 s (RMS) vs speech 10-40 s"
  ffmpeg -hide_banner -nostats -i src.mov -af "atrim=0:2,astats=measure_perchannel=none" -f null - 2>&1 | grep 'RMS level'
  ffmpeg -hide_banner -nostats -i src.mov -af "atrim=10:40,astats=measure_perchannel=none" -f null - 2>&1 | grep 'RMS level'
  echo "== silences > 1.5 s (candidates for chapter cards and fast-forwards)"
  # grep exits 1 when there is no long silence; that is a valid result, not a failure, under pipefail.
  ffmpeg -hide_banner -nostats -i src.mov -af "silencedetect=n=-35dB:d=1.5" -f null - 2>&1 \
    | { grep -oE 'silence_(start|end): [0-9.]+|silence_duration: [0-9.]+' || true; } | paste - - - | sed 's/silence_//g'
fi
echo "== frames"
ffmpeg -hide_banner -loglevel error -y -i src.mov -vf "fps=1/20,scale=480:-1,tile=4x6" -frames:v 1 montage.png
dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 src.mov)
ss=$(awk -v d="$dur" 'BEGIN{ s = d / 2; if (s > 30) s = 30; printf "%.2f", s }')
ffmpeg -hide_banner -loglevel error -y -ss "$ss" -i src.mov -frames:v 1 frame30.png
ffmpeg -hide_banner -loglevel error -y -i frame30.png -vf "crop=iw:160:0:0,scale=iw:320" chrome-top.png
echo "== pixel scale (2 = a Retina 2x capture: set video.width/height to half for a 1x deliverable, or keep native)"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 src.mov \
  | awk -F, '{ print "pixel_scale: " (($1 >= 2560 && $2 >= 1440) ? 2 : 1) }'
echo "montage.png (one frame per 20 s), frame30.png (full size, taken at ${ss}s), chrome-top.png (top 160 px, 2x): measure the browser chrome height here"
