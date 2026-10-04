#!/usr/bin/env bash
# Full build: soundtrack stems -> silent render of Main -> mix to -14 LUFS -> exports (mp4, srt, chapters).
#   tools/build.sh [version-label]
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
H="${AOS_VIDEO_MEDIA_ROOT:-$HOME/.aos/video/{{name}}}"
label="${1:-v1}"
cd "$P"
currency_mode=""
if [ -f "$P/qa.env" ]; then currency_mode="$(unset CURRENCY; . "$P/qa.env"; echo "${CURRENCY:-}")"; fi
if [ -f currency.json ]; then node tools/checks/currency.mjs currency.json --claims claims.json --export
elif [ "$currency_mode" = none ]; then echo "no currency ledger: qa.env declares a timeless topic (CURRENCY=none)"
else echo "currency.json missing: keep a ledger (R27) or declare CURRENCY=none in qa.env for a timeless topic" >&2; exit 1; fi
node tools/checks/claims.mjs
node tools/checks/screen-text.mjs
node --no-warnings tools/checks/joins.mts
node --no-warnings tools/check-plan.mts | tail -1
node --no-warnings tools/audio.mts
node tools/checks/input-manifest.mjs write "$H/renders/Main.inputs.json"
# the source the picture is rendered from, so QA can refuse to judge an export against changed code
(cd "$P" && find src -type f | sort | xargs cat | sha1sum | cut -d" " -f1) > "$H/renders/Main.src-hash"
# Rebuild only the segments whose sources changed (tools/render-cached.sh); AOS_RENDER_CACHE=0 renders Main whole.
if [ "${AOS_RENDER_CACHE:-1}" != 0 ]; then bash tools/render-cached.sh; else bash tools/render.sh Main; fi
bash tools/mix.sh "$H/renders/Main.mp4" "$H/renders/{{name}}-$label.mp4"
node tools/checks/input-manifest.mjs verify "$H/renders/Main.inputs.json"
node --no-warnings tools/package-outputs.mts
cp "$H/renders/{{name}}-$label.mp4" "$P/exports/{{name}}.mp4"
cp "$H/renders/Main.inputs.json" "$P/exports/input-manifest.json"
node tools/checks/input-manifest.mjs seal "$P/exports/input-manifest.json" "$P/exports/{{name}}.mp4" "$P/exports/{{name}}.srt"
echo "$P/exports/{{name}}.mp4"
