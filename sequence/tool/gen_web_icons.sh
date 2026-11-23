#!/usr/bin/env bash
# Build the web icons (favicon, PWA manifest icons, Apple touch icon and the
# link-preview image) from the brand PNGs in assets/branding. Requires
# ImageMagick 7 (`brew install imagemagick`).
#
# Usage: tool/gen_web_icons.sh
# Regenerate the brand PNGs first if the design changed:
#   python3 tool/gen_branding.py && tool/render_branding.sh
set -euo pipefail
cd "$(dirname "$0")/.."

src=assets/branding
out=web
mkdir -p "$out/icons"

# Full-bleed square icon: browsers and launchers apply their own mask.
for s in 192 512; do
  magick "$src/app_icon.png" -resize ${s}x${s} -strip "$out/icons/Icon-$s.png"
done
magick "$src/app_icon.png" -resize 180x180 -strip "$out/icons/apple-touch-icon.png"

# Maskable icons may be cropped to a circle of 80% diameter, so they are built
# from the adaptive-icon layers, whose chips sit inside that safe zone.
for s in 192 512; do
  magick "$src/app_icon_bg.png" "$src/app_icon_fg.png" -composite \
    -resize ${s}x${s} -strip "$out/icons/Icon-maskable-$s.png"
done

# Favicon: the full icon with rounded corners so it reads as a tile in a tab.
magick "$src/app_icon.png" -resize 64x64 \
  \( -size 64x64 xc:none -fill white -draw "roundrectangle 0,0 63,63 14,14" \) \
  -compose DstIn -composite -strip "$out/favicon.png"

# Link-preview image shown when an invite link is pasted into a chat app.
magick "$src/feature_graphic.png" -strip "$out/og-image.png"

echo "wrote $(cd "$out" && ls favicon.png og-image.png icons/* | tr '\n' ' ')"
