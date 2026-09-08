#!/usr/bin/env bash
# Process the narration of a screen recording into a broadcast-level stereo WAV.
# usage: voice-chain.sh <src.mov> <out.wav> [--window a:b ...] [--nr 12] [--nlm 2] [--no-nlm]
#   --window a:b   extra rumble removal (steep high-pass, low-shelf, denoise) only between a and b seconds;
#                  repeat for several windows. Use for a passing vehicle or a bump on the desk.
#   --dip a:b      shaped -16 dB gain dip between a and b (a pure-silence gap that still carries noise).
# Chain: mono | high-pass 90 Hz | afftdn (spectral) | anlmdn (non-local means) | de-esser | 3:1 compressor
#        | EQ (-2 dB @250, +2.5 dB @3.2k, +1 dB @120) | two-pass loudnorm -16 LUFS / -1.5 TP | limiter | stereo.
# Measured on a MacBook screen recording: gaps -52 -> -46 dB RMS while speech rose -31 -> -18.5 dB RMS.
# afftdn alone leaves gaps at -31 dB after make-up gain; anlmdn is what keeps them low.
set -euo pipefail
src="${1:?src}"; out="${2:?out.wav}"; shift 2
NR=12; NLM=2; WIN=(); DIP=()
while [ $# -gt 0 ]; do
  case "$1" in
    --window) WIN+=("$2"); shift 2;;
    --dip) DIP+=("$2"); shift 2;;
    --nr) NR="$2"; shift 2;;
    --nlm) NLM="$2"; shift 2;;
    --no-nlm) NLM=0; shift;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
chain="pan=mono|c0=c0,highpass=f=90,afftdn=nf=-48:nr=${NR}:tn=1"
[ "$NLM" != "0" ] && chain="$chain,anlmdn=s=${NLM}:p=0.002:r=0.006"
for w in "${WIN[@]:-}"; do
  [ -n "$w" ] || continue; a="${w%%:*}"; b="${w##*:}"; en="enable='between(t,${a},${b})'"
  chain="$chain,highpass=f=260:p=2:${en},highpass=f=260:p=2:${en},lowshelf=f=400:g=-10:${en},afftdn=nf=-40:nr=25:tn=1:${en}"
done
for d in "${DIP[@]:-}"; do
  [ -n "$d" ] || continue; a="${d%%:*}"; b="${d##*:}"
  chain="$chain,volume='1-0.85*clip(min(t-${a},${b}-t)/0.08,0,1)':eval=frame"
done
chain="$chain,deesser=i=0.25,acompressor=threshold=-26dB:ratio=3:attack=5:release=120:makeup=2"
chain="$chain,equalizer=f=250:t=q:w=1.2:g=-2,equalizer=f=3200:t=q:w=1:g=2.5,equalizer=f=120:t=q:w=1:g=1"
echo "pass 1: measure" >&2
json=$(ffmpeg -hide_banner -nostats -i "$src" -af "${chain},loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
read -r I TP LRA TH OFF < <(python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d['input_i'],d['input_tp'],d['input_lra'],d['input_thresh'],d['target_offset'])" <<<"$json")
ln="loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=${I}:measured_TP=${TP}:measured_LRA=${LRA}:measured_thresh=${TH}:offset=${OFF}:linear=true"
echo "pass 2: render (input ${I} LUFS)" >&2
ffmpeg -hide_banner -loglevel error -y -i "$src" -af "${chain},${ln},aresample=48000,alimiter=limit=0.89:level=false,aformat=channel_layouts=stereo" -c:a pcm_s16le "$out"
echo "== result" >&2
ffmpeg -hide_banner -nostats -i "$out" -af ebur128=peak=true -f null - 2>&1 | grep -E '^[[:space:]]+(I|LRA|Peak):' >&2
ffmpeg -hide_banner -nostats -i "$out" -af "atrim=10:40,astats=measure_perchannel=none" -f null - 2>&1 | grep 'RMS level' | sed 's/^.*RMS/speech 10-40 s RMS/' >&2
