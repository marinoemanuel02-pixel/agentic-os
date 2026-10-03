#!/usr/bin/env bash
# Render a composition to ~/.aos/video/{{name}}/renders/<id>.mp4 (video only; audio is mixed by tools/mix.sh).
#   tools/render.sh <CompositionId> [extra remotion flags]
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
H="${AOS_VIDEO_MEDIA_ROOT:-$HOME/.aos/video/{{name}}}"
bash "$P/tools/sync-app.sh"
cd "$H/app"
id="$1"; shift
node node_modules/@remotion/cli/remotion-cli.js render src/index.ts "$id" "$H/renders/$id.mp4" \
  --gl=angle --codec=h264 --crf=16 --pixel-format=yuv420p --muted --concurrency=4 --log=warn "$@"
echo "$H/renders/$id.mp4"
