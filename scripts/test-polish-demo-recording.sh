#!/usr/bin/env bash
# Runs the polish-demo-recording self-test (synthetic fixture, no ASR) when its tools are present,
# and skips cleanly otherwise so `make test` stays green on a machine without ffmpeg or uv.
set -euo pipefail
[ -d "/etc/profiles/per-user/$USER/bin" ] && PATH="/etc/profiles/per-user/$USER/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for t in ffmpeg ffprobe uv python3; do
  command -v "$t" >/dev/null || { echo "skip: $t not installed"; exit 0; }
done
bash "$REPO_ROOT/skills/polish-demo-recording/scripts/selftest.sh"
