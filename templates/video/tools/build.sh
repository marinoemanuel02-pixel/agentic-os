#!/usr/bin/env bash
# Full build: soundtrack stems -> silent render of Main -> mix to -14 LUFS -> exports (mp4, srt, chapters).
#   tools/build.sh [version-label] [wide|tall]
# tall renders MainTall (the native 9:16 film, captions drawn in) to exports/{{name}}-vertical.mp4 with its
# own sealed manifest (exports/input-manifest-vertical.json); the 16:9 export is left as it is.
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
. "$P/tools/media-root.sh"
label="${1:-v1}"
fmt="${2:-wide}"
if [ "$fmt" = tall ]; then comp=MainTall; film={{name}}-vertical; manifest=input-manifest-vertical; else comp=Main; film={{name}}; manifest=input-manifest; fi
cd "$P"
currency_mode=""
if [ -f "$P/qa.env" ]; then currency_mode="$(unset CURRENCY; . "$P/qa.env"; echo "${CURRENCY:-}")"; fi
if [ -f currency.json ]; then node tools/checks/currency.mjs currency.json --claims claims.json --export
elif [ "$currency_mode" = none ]; then echo "no currency ledger: qa.env declares a timeless topic (CURRENCY=none)"
else echo "currency.json missing: keep a ledger (R27) or declare CURRENCY=none in qa.env for a timeless topic" >&2; exit 1; fi
node tools/checks/claims.mjs
# Imported material (R35): rights, credits, fair-use limits and registry-only media paths, before any render.
mkdir -p "$H/qa"
node --no-warnings tools/timeline-json.mts > "$H/qa/timeline.json"
node tools/checks/assets.mjs "$P" --timeline "$H/qa/timeline.json" --public "$H/app/public" --report "$P/qa/assets.md"
node tools/checks/screen-text.mjs
node tools/checks/type-size.mjs
node --no-warnings tools/checks/joins.mts
node --no-warnings tools/check-plan.mts | tail -1
node --no-warnings tools/audio.mts
node tools/checks/input-manifest.mjs write "$H/renders/$comp.inputs.json"
# the source the picture is rendered from, so QA can refuse to judge an export against changed code
(cd "$P" && find src -type f | sort | xargs cat | sha1sum | cut -d" " -f1) > "$H/renders/$comp.src-hash"
# Rebuild only the segments whose sources changed (tools/render-cached.sh); AOS_RENDER_CACHE=0 renders Main whole.
# The segment cache is keyed for Main: the tall film renders whole.
if [ "$comp" = Main ] && [ "${AOS_RENDER_CACHE:-1}" != 0 ]; then bash tools/render-cached.sh; else bash tools/render.sh "$comp"; fi
bash tools/mix.sh "$H/renders/$comp.mp4" "$H/renders/$film-$label.mp4"
node tools/checks/input-manifest.mjs verify "$H/renders/$comp.inputs.json"
node --no-warnings tools/package-outputs.mts
cp "$H/renders/$film-$label.mp4" "$P/exports/$film.mp4"
cp "$H/renders/$comp.inputs.json" "$P/exports/$manifest.json"
node tools/checks/input-manifest.mjs seal "$P/exports/$manifest.json" "$P/exports/$film.mp4" "$P/exports/{{name}}.srt"
echo "$P/exports/$film.mp4"
