#!/usr/bin/env bash
# Render the self-test fixture: a 24 s moving test pattern with a synthetic narration track,
# plus a 30 s music bed. Nothing here is committed; selftest.sh regenerates it on every run.
#   video: testsrc2 (moving pattern, so zooms and speed-ups are visible in verify.png)
#   voice: a 220 Hz tone with 4 Hz amplitude modulation (syllable-like), gated into four bursts
#          0.5-4.0, 5.5-9.0, 12.0-15.0, 20.0-23.5 s -> gaps of 1.5, 3.0 and 5.0 s
#   music: a 110 Hz sine at low level
# usage: make-fixture.sh <outdir>
set -euo pipefail
out="${1:?outdir}"
mkdir -p "$out"
gate='(between(t,0.5,4)+between(t,5.5,9)+between(t,12,15)+between(t,20,23.5))'
voice="0.5*sin(2*PI*220*t)*(0.6+0.4*sin(2*PI*4*t))*${gate}"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30" \
  -f lavfi -i "aevalsrc=exprs='${voice}':s=48000:c=stereo" \
  -t 24 -c:v libx264 -crf 18 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 128k \
  "$out/fixture.mp4"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "sine=f=110:r=48000" -af "volume=0.1,aformat=channel_layouts=stereo" -t 30 \
  "$out/music.wav"
echo "fixture: $out/fixture.mp4 (24 s), $out/music.wav (30 s)"
