#!/usr/bin/env bash
# Finish the short: render Main, normalise loudness (-14 LUFS, TP <= -1), write the SRT, cover and contact sheet.
# Usage: bash tools/finish.sh <version>   -> exports/cant-escape-ai-<version>.mp4 (+ .srt, -cover.jpg, -sheet.jpg)
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd -W)"  # Windows-style, so python and ffmpeg read the same path
H="${AOS_VIDEO_MEDIA_ROOT:-$HOME/.aos/video/$(basename "$P")}"
v="${1:?version}"
name="$(basename "$P")-$v"
mkdir -p "$P/exports" "$H/renders"
raw="$H/renders/$name-raw.mp4"
out="$P/exports/$name.mp4"
bash "$P/tools/sync-app.sh"
(cd "$H/app" && node node_modules/@remotion/cli/remotion-cli.js render src/index.ts Main "$raw" \
  --gl=angle --codec=h264 --crf=17 --pixel-format=yuv420p --audio-codec=aac --audio-bitrate=256k --concurrency=3 --log=warn)
# two-pass loudnorm on the audio only; picture is copied
m=$(ffmpeg -nostdin -hide_banner -i "$raw" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | sed -n '/^{/,/^}/p')
g() { echo "$m" | grep "\"$1\"" | sed 's/.*: "\(.*\)".*/\1/'; }
ffmpeg -nostdin -v error -y -i "$raw" -vf "scale=out_range=tv,format=yuv420p" -c:v libx264 -crf 17 -preset slow -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$(g input_i):measured_TP=$(g input_tp):measured_LRA=$(g input_lra):measured_thresh=$(g input_thresh):offset=$(g target_offset):linear=true,aresample=48000" \
  -c:a aac -b:a 256k -movflags +faststart "$out"
python "$P/tools/srt.py" "$P/exports/$name.srt"
# cover: the last shot (the one the film ends on, and loops from)
cover_t=$(python -c "import json;e=json.load(open(r'$P/src/data/edit.json'));s=e['shots'][-1];print((s['from']+s['frames']-10)/30)")
ffmpeg -nostdin -v error -y -ss "$cover_t" -i "$out" -frames:v 1 -q:v 2 "$P/exports/$name-cover.jpg"
# contact sheet: the middle of every shot
python - "$P" "$out" "$H/renders/sheet" <<'EOF'
import json, subprocess, sys, os
p, video, d = sys.argv[1:4]
os.makedirs(d, exist_ok=True)
e = json.load(open(os.path.join(p, "src/data/edit.json")))
files = []
for s in e["shots"]:
    t = (s["from"] + s["frames"] / 2) / e["fps"]
    f = os.path.join(d, f"{s['id']}.png")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", f"{t:.2f}", "-i", video, "-frames:v", "1", "-vf", "scale=216:-1", f], check=True)
    files.append(f)
subprocess.run(["magick", "montage", *files, "-tile", "10x", "-geometry", "+2+2", "-background", "#111", os.path.join(p, "exports", os.path.basename(video).replace(".mp4", "-sheet.jpg"))], check=True)
EOF
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate -show_entries format=duration -of compact "$out"
ffmpeg -nostdin -hide_banner -nostats -i "$out" -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+(I|Peak):" | tail -2
# Enforced gates (the shorts counterpart of qa.sh sections 1-4 plus its static gates). The outputs above stay on failure.
mkdir -p "$P/qa" "$H/qa"
R="$P/qa/report.md"; fail=0
ok() { echo "- PASS $*" >> "$R"; }; bad() { echo "- FAIL $*" >> "$R"; fail=1; }
echo "# QA report: $(basename "$out") ($(date '+%Y-%m-%d %H:%M'))" > "$R"; echo >> "$R"
# gate <label> <command...>: run it, keep its output in the media root, record PASS or FAIL (never aborts under set -e)
gate() {
  local label="$1" log rc=0; shift
  log="$H/qa/finish-$(echo "$label" | tr -c 'A-Za-z0-9' '-').log"
  "$@" > "$log" 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then ok "$label"; else bad "$label (exit $rc):"; head -20 "$log" | sed 's/^/  /' >> "$R"; fi
}
currency_mode="$( [ -f "$P/qa.env" ] && (unset CURRENCY; . "$P/qa.env"; echo "${CURRENCY:-}") || true )"
if [ -f "$P/currency.json" ]; then gate "currency ledger current" node "$P/tools/checks/currency.mjs" "$P/currency.json" --claims "$P/claims.json" --export
elif [ "$currency_mode" = none ]; then ok "no currency ledger: qa.env declares a timeless topic (CURRENCY=none)"
else bad "currency.json missing: keep a ledger (R27) or declare CURRENCY=none in qa.env for a timeless topic"; fi
gate "claims ledger complete" node "$P/tools/checks/claims.mjs"
gate "screen-text ledger coverage" node "$P/tools/checks/screen-text.mjs"
gate "type size (rubric 4, R58)" node "$P/tools/checks/type-size.mjs"
gate "voice scale receipt (R55)" node "$P/tools/checks/voice-scale.mjs" --receipt "$P/src/data/voice-scale.json" --voice "$P/src/data/words.sha256.json"
# stream format, duration, loudness, black/frozen frames and captions of the export itself (QA_SIZE/QA_MIN_S/QA_MAX_S from qa.env)
dlog="$H/qa/finish-delivery.log"; drc=0
node "$P/tools/checks/delivery.mjs" "$out" "$P/exports/$name.srt" > "$dlog" 2>&1 || drc=$?
cat "$dlog" >> "$R"
[ "$drc" = 0 ] || fail=1
echo >> "$R"; if [ "$fail" = 0 ]; then echo "**All technical checks pass.**" >> "$R"; else echo "**Technical checks FAILED.**" >> "$R"; fi
cat "$R"
echo "$out"
echo "report: $R"
exit "$fail"
