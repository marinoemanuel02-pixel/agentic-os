#!/usr/bin/env bash
# Render chosen frames from one bundle, 4 at a time, and lay them out on a sheet for review:
#   tools/frames.sh <sheet-name> S01:20 S01:140 S02:60 ...   -> ~/.aos/video/{{name}}/frames/<sheet-name>.jpg
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
H="$HOME/.aos/video/{{name}}"
name="$1"; shift
bash "$P/tools/sync-app.sh"
cd "$H/app"
node node_modules/@remotion/cli/remotion-cli.js bundle src/index.ts --out-dir "$H/bundle" --log=warn >/dev/null
files=()
n=0
for spec in "$@"; do
  id="${spec%%:*}"; fr="${spec##*:}"
  out="$H/frames/$id-$fr.png"
  files+=("$out")
  node node_modules/@remotion/cli/remotion-cli.js still "$H/bundle" "$id" "$out" --frame="$fr" --gl=angle --log=error >/dev/null &
  n=$((n + 1))
  if [ $((n % 4)) = 0 ]; then wait; fi
done
wait
magick montage "${files[@]}" -tile 2x -geometry 960x540+4+4 -background "#222" -fill "#ddd" -pointsize 18 -set label '%t' "$H/frames/$name.jpg"
echo "$H/frames/$name.jpg"
