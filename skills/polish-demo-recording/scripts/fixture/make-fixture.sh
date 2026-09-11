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
# Two halves for the multi-clip variant (re-encoded so each starts on a keyframe), and a voice track that starts
# 0.35 s early (silence prepended), for the separate-voice variant: voice.offset = -0.35.
ffmpeg -hide_banner -loglevel error -y -i "$out/fixture.mp4" -t 12 -c:v libx264 -crf 18 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 128k "$out/a.mp4"
ffmpeg -hide_banner -loglevel error -y -ss 12 -i "$out/fixture.mp4" -t 12 -c:v libx264 -crf 18 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 128k "$out/b.mp4"
ffmpeg -hide_banner -loglevel error -y -i "$out/fixture.mp4" -vn -af "adelay=delays=350:all=1" -c:a pcm_s16le "$out/vo.wav"
# The same early track cut to 20.35 s, so after the -0.35 trim the voice ends 4 s before the video: the master mux must
# pad it with silence, not truncate the video to it.
ffmpeg -hide_banner -loglevel error -y -i "$out/vo.wav" -t 20.35 -c:a pcm_s16le "$out/vo-short.wav"
# Pair for the positive-offset check: seeded pink noise gated into the same bursts, and a copy that starts 2 s late
# (voice.offset = +2.0). Noise, not the tone: the tone repeats every 0.25 s, so its correlation has near-equal peaks
# one AM cycle apart and a different decoder can tip the argmax; noise has one peak. PCM both, so no AAC priming.
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "anoisesrc=color=pink:seed=7:r=48000:a=0.5" \
  -af "volume='${gate}':eval=frame" -t 24 -c:a pcm_s16le "$out/noise-ref.wav"
ffmpeg -hide_banner -loglevel error -y -ss 2.0 -i "$out/noise-ref.wav" -c:a pcm_s16le "$out/noise-late.wav"
# probe.sh edge cases: a recording with no audio stream, and a 12 s clip with a continuous tone (no silence at all).
ffmpeg -hide_banner -loglevel error -y -i "$out/fixture.mp4" -an -c:v copy "$out/noaudio.mp4"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=640x360:rate=30" -f lavfi -i "sine=f=440:r=48000" \
  -t 12 -c:v libx264 -crf 24 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 96k -ac 2 "$out/tone12.mp4"
# A 540x960 portrait copy of the fixture (letterboxed, same audio) for the vertical-video variant.
ffmpeg -hide_banner -loglevel error -y -i "$out/fixture.mp4" \
  -vf "scale=540:960:force_original_aspect_ratio=decrease,pad=540:960:(ow-iw)/2:(oh-ih)/2" \
  -c:v libx264 -crf 18 -preset veryfast -pix_fmt yuv420p -c:a copy "$out/portrait.mp4"
# A 2 s bumper (solid colour with a tone) for the ops variant.
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "color=c=0x3b5bfd:s=1920x1080:r=30" -f lavfi -i "sine=f=440:r=48000" \
  -t 2 -c:v libx264 -crf 18 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 128k "$out/bumper.mp4"
echo "fixture: $out/fixture.mp4 (24 s), $out/music.wav (30 s)"
