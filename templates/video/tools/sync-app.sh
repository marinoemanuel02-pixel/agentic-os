#!/usr/bin/env bash
# Copy the config files into the render app folder (outside OneDrive). src/ is a junction, so code needs no copy.
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
H="${AOS_VIDEO_MEDIA_ROOT:-$HOME/.aos/video/{{name}}}/app"
cp "$P/tools/remotion.config.ts" "$P/tools/package.json" "$P/tools/tsconfig.json" "$H/"
