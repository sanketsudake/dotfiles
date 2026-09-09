#!/usr/bin/env bash
# Word-timestamp transcription into the JSON shape build_demo.py reads (mlx-whisper's).
# usage: transcribe.sh <audio> <outdir> [--backend auto|mlx|faster|none] [--language xx] [--model name] [--print]
#   auto    mlx-whisper on Apple Silicon macOS, faster-whisper elsewhere
#   none    do nothing: you supply the transcript (another tool, or a corrected file)
#   --print show the command and exit (used by the self-test; no model is downloaded)
# Output: <outdir>/<stem>.json  e.g. whisper/audio16k.json
set -euo pipefail
audio="${1:?audio}"; outdir="${2:?outdir}"; shift 2
BACKEND=auto; LANG_=""; MODEL=""; PRINT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) BACKEND="$2"; shift 2;;
    --language) LANG_="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --print) PRINT=1; shift;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
if [ "$BACKEND" = auto ]; then
  if [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]; then BACKEND=mlx; else BACKEND=faster; fi
fi
stem="$(basename "${audio%.*}")"
mkdir -p "$outdir"
case "$BACKEND" in
  none)
    echo "backend none: write $outdir/$stem.json yourself (segments[].words[] {start, end, word})"; exit 0;;
  mlx)
    cmd=(uvx --from mlx-whisper==0.4.3 mlx_whisper "$audio" --model "${MODEL:-mlx-community/whisper-large-v3-turbo}"
         --word-timestamps True --output-format json --output-dir "$outdir")
    [ -n "$LANG_" ] && cmd+=(--language "$LANG_")
    ;;
  faster)
    py='
import json, sys
from faster_whisper import WhisperModel
audio, out, model, lang = sys.argv[1:5]
m = WhisperModel(model or "large-v3-turbo", compute_type="int8")
segs, info = m.transcribe(audio, word_timestamps=True, language=lang or None)
res = {"text": "", "segments": [], "language": info.language}
for i, s in enumerate(segs):
    words = [{"start": w.start, "end": w.end, "word": w.word} for w in (s.words or [])]
    res["segments"].append({"id": i, "start": s.start, "end": s.end, "text": s.text, "words": words})
    res["text"] += s.text
json.dump(res, open(out, "w"), indent=1)
print("wrote", out, "language", info.language)
'
    cmd=(uv run --with faster-whisper python3 -c "$py" "$audio" "$outdir/$stem.json" "$MODEL" "$LANG_")
    ;;
  *) echo "unknown backend $BACKEND" >&2; exit 2;;
esac
if [ "$PRINT" = 1 ]; then printf '%s\n' "backend=$BACKEND language=${LANG_:-auto}" "${cmd[*]}"; exit 0; fi
"${cmd[@]}"
