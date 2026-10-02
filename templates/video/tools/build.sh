#!/usr/bin/env bash
# Full build: soundtrack stems -> silent render of Main -> mix to -14 LUFS -> exports (mp4, srt, chapters).
#   tools/build.sh [version-label]
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
H="$HOME/.aos/video/{{name}}"
label="${1:-v1}"
cd "$P"
node --no-warnings tools/check-plan.mts | tail -1
node --no-warnings tools/audio.mts
# the source the picture is rendered from, so QA can refuse to judge an export against changed code
(cd "$P" && find src -type f | sort | xargs cat | sha1sum | cut -d" " -f1) > "$H/renders/Main.src-hash"
bash tools/render.sh Main
bash tools/mix.sh "$H/renders/Main.mp4" "$H/renders/{{name}}-$label.mp4"
node --no-warnings tools/package-outputs.mts
cp "$H/renders/{{name}}-$label.mp4" "$P/exports/{{name}}.mp4"
echo "$P/exports/{{name}}.mp4"
