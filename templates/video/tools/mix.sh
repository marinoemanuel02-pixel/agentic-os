#!/usr/bin/env bash
# Mix the stems (music ducked under the voice), normalise to YouTube loudness (-14 LUFS, TP -1.5 dBTP, two
# passes) and mux with a silent render.
#   tools/mix.sh <video.mp4> <out.mp4> [start_seconds duration_seconds]
# With start/duration, the stems are cut to that window (to preview one shot with its real soundtrack).
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
. "$P/tools/media-root.sh"
A="$H/audio"
video="$1"; out="$2"; start="${3:-0}"; dur="${4:-}"
if [ -z "$dur" ]; then dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video"); fi
mkdir -p "$H/renders"
tmp="$H/renders/mix-tmp.wav"

# Stem balance (measured: music.wav -14.4 LUFS, vo.wav -22.5, sfx.wav -23.1): the voice must sit well above the
# music, so the voice is raised and music and effects lowered before the sum.
graph="[0:a]atrim=start=${start}:duration=${dur},asetpts=N/SR/TB,volume=0.22[mu];
[1:a]atrim=start=${start}:duration=${dur},asetpts=N/SR/TB,volume=0.5[fx];
[2:a]atrim=start=${start}:duration=${dur},asetpts=N/SR/TB,volume=2.2,asplit=2[vo][sc];
[mu][sc]sidechaincompress=threshold=0.02:ratio=8:attack=15:release=400:makeup=1[duck];
[vo][duck][fx]amix=inputs=3:normalize=0,afade=t=in:d=0.05,afade=t=out:st=$(awk "BEGIN{print $dur - 0.08}"):d=0.08,aresample=192000,alimiter=limit=0.5:attack=1:release=80:level=false,aresample=48000[mix]"
# ^ the sum is peak-limited (4x oversampled, -6 dBFS) BEFORE loudnorm, so the linear second pass can add its gain
#   without pushing transients past the -1.5 dBTP ceiling (without it the true peak landed at +0.1 dBTP).

ffmpeg -v error -y -i "$A/music.wav" -i "$A/sfx.wav" -i "$A/vo.wav" -filter_complex "$graph" -map "[mix]" -ar 48000 "$tmp"

# loudnorm pass 1: measure
m=$(ffmpeg -hide_banner -i "$tmp" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | sed -n '/^{/,/^}/p')
get() { echo "$m" | grep "\"$1\"" | sed 's/.*: "\(.*\)".*/\1/'; }
ln="loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$(get input_i):measured_TP=$(get input_tp):measured_LRA=$(get input_lra):measured_thresh=$(get input_thresh):offset=$(get target_offset):linear=true"

# pass 2: apply and mux. Remotion captures JPEG frames, so its h264 comes out full range (yuvj420p): convert to
# TV-range yuv420p, BT.709, which is what YouTube expects (tools/qa.sh checks it).
ffmpeg -v error -y -i "$video" -i "$tmp" \
  -filter_complex "[0:v]scale=in_range=pc:out_range=tv,format=yuv420p[v];[1:a]${ln},aresample=48000[a]" -map "[v]" -map "[a]" \
  -c:v libx264 -crf 19 -maxrate 16M -bufsize 32M -preset slow -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:a aac -b:a 256k -shortest -movflags +faststart "$out"
echo "$out"
