#!/usr/bin/env bash
# Render Main through the per-segment cache: segments whose key is unchanged are reused from renders/cache/, the rest
# render from one shared bundle (AOS_RENDER_JOBS at a time, default 2), then all are joined losslessly into
# renders/Main.mp4 with a frame-count check. Needs renders/Main.inputs.json (build.sh writes it first).
#   tools/render-cached.sh
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
. "$P/tools/media-root.sh"
JOBS="${AOS_RENDER_JOBS:-2}"
CONC=$(( 4 / JOBS > 0 ? 4 / JOBS : 1 ))
C="$H/renders/cache"
mkdir -p "$C"
node --no-warnings "$P/tools/cache/plan.mts" "$H/renders/Main.inputs.json" > "$C/plan.txt"
bash "$P/tools/sync-app.sh"
cd "$H/app"
B="$H/renders/cache-bundle"
rm -rf "$B"
node node_modules/@remotion/cli/remotion-cli.js bundle src/index.ts --out-dir "$B" --log=warn > /dev/null
hits=0; misses=0; started=$(date +%s)
: > "$C/log.txt"
while read -r key first last shots; do
  out="$C/$key.mp4"
  if [ -f "$out" ]; then hits=$((hits + 1)); echo "hit  $shots" >> "$C/log.txt"; continue; fi
  misses=$((misses + 1)); echo "miss $shots" >> "$C/log.txt"
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
  ( node node_modules/@remotion/cli/remotion-cli.js render "$B" Main "$out.part.mp4" --frames="$first-$last" \
      --gl=angle --codec=h264 --crf=16 --pixel-format=yuv420p --muted --concurrency="$CONC" --log=error \
    && mv "$out.part.mp4" "$out" ) &
done < "$C/plan.txt"
wait
total=$(awk '{n += $3 - $2 + 1} END {print n}' "$C/plan.txt")
awk -v c="$C" '{print c "/" $1 ".mp4"}' "$C/plan.txt" > "$C/parts.txt"
node "$P/tools/cache/concat.mjs" "$H/renders/Main.mp4" "$total" "$C/parts.txt"
echo "render cache: $hits hit(s), $misses miss(es), $(( $(date +%s) - started )) s" | tee -a "$C/log.txt"
echo "$H/renders/Main.mp4"
