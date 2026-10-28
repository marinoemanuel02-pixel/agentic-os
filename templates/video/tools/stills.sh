#!/usr/bin/env bash
# Review sheet of the assembled composition: bundle once, render one Main still per listed shot at a point inside it.
# Usage: bash tools/stills.sh <sheet-name> S05:0.9 S11:0.8 ...   (fraction of the shot, default 0.5)
# -> <media>/frames/<sheet-name>.png (tiled at 360 px wide). Fast check of cards, overlays and captions before a render.
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd -W)"
H="${AOS_VIDEO_MEDIA_ROOT:-$HOME/.aos/video/$(basename "$P")}"
name="$1"; shift
bash "$P/tools/sync-app.sh"
cd "$H/app"
node node_modules/@remotion/cli/remotion-cli.js bundle src/index.ts --out-dir "$H/bundle" --log=warn >/dev/null
files=()
for spec in "$@"; do
  id="${spec%%:*}"; frac="${spec#*:}"; [ "$frac" = "$spec" ] && frac=0.5
  f=$(python -c "import json;e={s['id']:s for s in json.load(open(r'$P/src/data/edit.json'))['shots']}[\"$id\"];print(e['from']+int(e['frames']*$frac))")
  node node_modules/@remotion/cli/remotion-cli.js still "$H/bundle" Main "$H/frames/$id.png" --frame="$f" --gl=angle --log=warn >/dev/null
  files+=("$H/frames/$id.png")
done
magick "${files[@]}" -resize 360x +append "$H/frames/$name.png"
echo "$H/frames/$name.png"
