#!/usr/bin/env bash
# Render the brand SVGs to PNG. Requires Inkscape (best SVG fidelity).
# Usage: python3 tool/gen_branding.py && tool/render_branding.sh
set -euo pipefail
cd "$(dirname "$0")/../assets/branding"
for f in app_icon app_icon_fg app_icon_bg; do
  inkscape "$f.svg" --export-type=png --export-filename="$f.png" -w 1024 -h 1024
done
inkscape feature_graphic.svg --export-type=png \
  --export-filename=feature_graphic.png -w 1024 -h 500
echo "rendered $(ls *.png | tr '\n' ' ')"
