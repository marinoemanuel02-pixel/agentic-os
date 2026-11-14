#!/usr/bin/env bash
# Compare takes of one keyframe pair across providers: endpoint RMSE against the keyframes, the frames where motion
# starts and stops, and a 16-frame contact sheet each.
#   measure-takes.sh <dir with <name>.mp4 takes> <start keyframe 1280x720 png> <end keyframe png> <name>...
set -u
D=$1; KA=$2; KB=$3; shift 3
cd "$D"
for p in "$@"; do
  f=$p.mp4
  [ -f "$f" ] || { echo "$p: missing"; continue; }
  n=$(ffprobe -v error -count_frames -select_streams v -show_entries stream=nb_read_frames -of csv=p=0 "$f")
  ffmpeg -nostdin -loglevel error -y -i "$f" -vf "scale=1280:720" -frames:v 1 "$p-first.png"
  ffmpeg -nostdin -loglevel error -y -i "$f" -vf "select=eq(n\,$((n-1))),scale=1280:720" -frames:v 1 "$p-last.png"
  a=$(magick compare -metric RMSE "$p-first.png" "$KA" null: 2>&1 | sed -E 's/.*\(([0-9.e-]+)\).*/\1/')
  b=$(magick compare -metric RMSE "$p-last.png" "$KB" null: 2>&1 | sed -E 's/.*\(([0-9.e-]+)\).*/\1/')
  ffmpeg -nostdin -loglevel error -i "$f" -vf "scale=320:-1,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=$p-motion.txt" -f null -
  # first frame where motion starts (> 0.2) and last frame still moving (> 0.1), of n frames
  mv=$(grep -o 'YAVG=[0-9.e-]*' "$p-motion.txt" | cut -d= -f2 | awk '{v=$1+0; if(start==0 && v>0.2) start=NR; if(v>0.1) last=NR} END{printf "%d %d", start, last}')
  ffmpeg -nostdin -loglevel error -y -i "$f" -vf "fps=$(awk -v n=$n "BEGIN{printf \"%.3f\", 16/(n/24)}"),scale=320:-1,tile=8x2" -frames:v 1 "$p-sheet.png"
  echo "$p: frames=$n firstRMSE=$a lastRMSE=$b motion(start,last)=$mv"
done
