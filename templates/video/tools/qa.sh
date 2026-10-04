#!/usr/bin/env bash
# Technical QA of a finished export. Writes qa/report.md and qa/contact-sheet.jpg; exit 1 on any failure.
#   tools/qa.sh exports/{{name}}.mp4 exports/{{name}}.srt
set -uo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
video="$1"; srt="$2"
H="${AOS_VIDEO_MEDIA_ROOT:-$HOME/.aos/video/{{name}}}"
mkdir -p "$P/qa" "$H/qa/shots"
R="$P/qa/report.md"; fail=0
ok() { echo "- PASS $*" >> "$R"; }; bad() { echo "- FAIL $*" >> "$R"; fail=1; }
echo "# QA report: $(basename "$video") ($(date '+%Y-%m-%d %H:%M'))" > "$R"; echo >> "$R"

# Source coverage and camera joins are gates, not proof of factual truth or full-size legibility.
if [ -f "$P/currency.json" ]; then node "$P/tools/checks/currency.mjs" "$P/currency.json" || { bad "currency ledger stale or invalid"; cat "$R"; exit 1; }; fi
node "$P/tools/checks/claims.mjs" || { bad "claims ledger incomplete"; cat "$R"; exit 1; }
node "$P/tools/checks/screen-text.mjs" || { bad "screen-text ledger coverage incomplete"; cat "$R"; exit 1; }
node --no-warnings "$P/tools/checks/joins.mts" || { bad "camera joins invalid"; cat "$R"; exit 1; }

# Refuse mixed-input evidence before decoding or rendering any proxy.
if node "$P/tools/checks/input-manifest.mjs" verify "$P/exports/input-manifest.json" "$video" "$srt" > "$H/qa/manifest.log" 2>&1; then
  ok "export input manifest matches picture, public assets, voice/music, fonts, config and runtime"
else
  bad "export input manifest missing or changed; rebuild before QA"
  cat "$H/qa/manifest.log" >> "$R"
  cat "$R"
  exit 1
fi

# 0. the export must come from the current src/ (the motion proxy below renders from src/, so a later edit would
#    make QA judge two different films); tools/build.sh records the hash it rendered from
now=$(cd "$P" && find src -type f | sort | xargs cat | sha1sum | cut -d" " -f1)
built=$(cat "$H/renders/Main.src-hash" 2>/dev/null || echo none)
[ "$now" = "$built" ] && ok "export built from the current src/" || bad "src/ changed since the export was built (rebuild before QA)"

# 1. stream format
v=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt -of csv=p=0 "$video" | tr -d '\r' | sed 's/,$//')
a=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$video" | tr -d '\r' | sed 's/,$//')
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video")
[[ "$v" == h264,1920,1080,yuv420p,30/1 ]] && ok "video $v" || bad "video $v (want h264,1920,1080,yuv420p,30/1)"
[[ "$a" == aac,48000,2 ]] && ok "audio $a" || bad "audio $a (want aac,48000,2)"
# target length from the brief: qa.env sets QA_MIN_S / QA_MAX_S per project; values already in the environment win
env_min="${QA_MIN_S:-}"; env_max="${QA_MAX_S:-}"
[ -f "$P/qa.env" ] && . "$P/qa.env"
[ -n "$env_min" ] && QA_MIN_S="$env_min"
[ -n "$env_max" ] && QA_MAX_S="$env_max"
min="${QA_MIN_S:-60}"; max="${QA_MAX_S:-90}"
awk "BEGIN{exit !($dur >= $min && $dur <= $max)}" && ok "duration ${dur}s ($min-$max)" || bad "duration ${dur}s (want $min-$max)"

# 2. loudness (YouTube: -14 LUFS +-1, true peak <= -1 dBTP)
L=$(ffmpeg -hide_banner -nostats -i "$video" -af ebur128=peak=true -f null - 2>&1 | sed -n '/Summary/,$p')
I=$(echo "$L" | awk '/ I:/{print $2}'); TP=$(echo "$L" | awk '/Peak:/{print $2}' | tail -1)
awk "BEGIN{exit !($I >= -15 && $I <= -13)}" && ok "integrated loudness $I LUFS" || bad "integrated loudness $I LUFS"
awk "BEGIN{exit !($TP <= -1.0)}" && ok "true peak $TP dBTP" || bad "true peak $TP dBTP (want <= -1)"

# 3. black and frozen frames (the end card fades in from black: allow up to 0.5 s at the very start of S27)
B=$(ffmpeg -hide_banner -nostats -i "$video" -vf "blackdetect=d=0.5:pix_th=0.06" -an -f null - 2>&1 | grep -o "black_start:[0-9.]* black_end:[0-9.]* black_duration:[0-9.]*")
[ -z "$B" ] && ok "no black segment >= 0.5 s" || { echo "  black: $B" >> "$R"; bad "black segments found (see above; judge against intended fades)"; }
F=$(ffmpeg -hide_banner -nostats -i "$video" -vf "freezedetect=n=0.0008:d=1.0" -an -f null - 2>&1 | grep -o "freeze_start: [0-9.]*\|freeze_duration: [0-9.]*" | paste - - )
[ -z "$F" ] && ok "no frozen segment >= 1 s" || { echo "  frozen: $F" >> "$R"; bad "frozen segments found"; }

# 4. captions inside the duration, ordered, no overlaps
last=$(grep -- "-->" "$srt" | tail -1 | sed 's/.*--> //; s/,/./' | awk -F: '{print $1*3600+$2*60+$3}')
cues=$(grep -c -- "-->" "$srt")
order=$(grep -- "-->" "$srt" | sed 's/,/./g' | awk -F' --> ' '{split($1,a,":");split($2,b,":");s=a[1]*3600+a[2]*60+a[3];e=b[1]*3600+b[2]*60+b[3]; if(s<pe||e<=s) bad++; pe=e} END{print bad+0}')
awk "BEGIN{exit !($last <= $dur)}" && ok "$cues captions, last ends at ${last}s <= ${dur}s" || bad "last caption ends at ${last}s > ${dur}s"
[ "$order" = 0 ] && ok "captions ordered, no overlaps" || bad "$order caption(s) overlap or are empty"

# 5. contact sheet: one frame at the middle of every shot (for the craft review and the local-model screen)
node --no-warnings -e '
const { buildShots } = await import("file:///" + process.argv[1].replace(/\\/g, "/") + "/src/data/plan.ts");
for (const s of buildShots()) console.log(s.id, ((s.from + s.frames / 2) / 30).toFixed(3));
' "$P" > "$H/qa/shot-mids.txt"
rm -f "$H"/qa/shots/*.png
while read -r id t; do ffmpeg -v error -y -ss "$t" -i "$video" -frames:v 1 "$H/qa/shots/$id.png"; done < "$H/qa/shot-mids.txt"
magick montage "$H"/qa/shots/*.png -tile 6x -geometry 480x270+4+4 -background "#222" -fill "#bbb" -pointsize 14 "$P/qa/contact-sheet.jpg"
ok "contact sheet: qa/contact-sheet.jpg ($(wc -l < "$H/qa/shot-mids.txt") shots)"

# 6. motion (rule R17): a quarter-size proxy of Main without line boil or grain, then tools/checks/motion.mjs
#    (snaps = travelling moves that start at full speed; banned expo/back curves in src/). Report: qa/motion.md
#    The proxy is rendered fresh from the current src/ every run, so it can never describe an older cut.
proxy="$H/renders/Main-qa.mp4"
node "$P/tools/checks/input-manifest.mjs" verify "$P/exports/input-manifest.json" >/dev/null \
  || { bad "inputs changed before proxy render; evidence invalid"; cat "$R"; exit 1; }
rm -f "$proxy"
bash "$P/tools/sync-app.sh"
if (cd "$H/app" && node node_modules/@remotion/cli/remotion-cli.js render src/index.ts Main "$proxy" \
    --scale=0.25 --props='{"qa":true}' --gl=angle --codec=h264 --crf=18 --muted --concurrency=4 --log=warn >/dev/null) && [ -s "$proxy" ]; then
  node --no-warnings "$P/tools/checks/motion.mjs" "$proxy" "$P/qa/motion.md" > /dev/null \
    && ok "motion check (qa/motion.md)" || bad "motion check: snaps or banned curves (see qa/motion.md)"
else
  bad "motion check: the proxy render failed"
fi

node "$P/tools/checks/input-manifest.mjs" verify "$P/exports/input-manifest.json" >/dev/null \
  && ok "inputs unchanged through QA" || bad "inputs changed during QA; evidence invalid"

pacing_args=(); [ -f "$P/src/data/shots.json" ] && pacing_args+=(--shots "$P/src/data/shots.json"); pacing_args+=(--claims "$P/claims.json" --lines "$P/src/data/lines.json")
if node "$P/tools/checks/pacing.mjs" "$video" "${pacing_args[@]}" --out "$P/qa/pacing" > "$H/qa/pacing.log" 2>&1; then
  ok "pacing report: qa/pacing.md (reviewer judgment)"
else
  echo "- Pacing report unavailable (see media root qa/pacing.log)" >> "$R"
fi

echo >> "$R"; [ $fail = 0 ] && echo "**All technical checks pass.**" >> "$R" || echo "**Technical checks FAILED.**" >> "$R"
cat "$R"; exit $fail
