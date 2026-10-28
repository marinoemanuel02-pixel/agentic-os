#!/usr/bin/env bash
# Render stills from one bundle: tools/still.sh <frame> <CompositionId>... -> ~/.aos/video/{{name}}/frames/<id>-<frame>.png
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
. "$P/tools/media-root.sh"
bash "$P/tools/sync-app.sh"
cd "$H/app"
frame="$1"; shift
node node_modules/@remotion/cli/remotion-cli.js bundle src/index.ts --out-dir "$H/bundle" --log=warn >/dev/null
for id in "$@"; do
  node node_modules/@remotion/cli/remotion-cli.js still "$H/bundle" "$id" "$H/frames/$id-$frame.png" --frame="$frame" --gl=angle --log=warn | tail -1
  echo "$H/frames/$id-$frame.png"
done
