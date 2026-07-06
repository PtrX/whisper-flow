#!/usr/bin/env bash
set -euo pipefail

# Regenerates Resources/AppIcon.icns from Resources/AppIcon.svg using
# macOS's built-in QuickLook SVG renderer (qlmanage) — no third-party
# SVG rasterizer needed.

SVG="Resources/AppIcon.svg"
ICONSET="Resources/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() {
  local size=$1
  local outfile=$2
  qlmanage -t -s "$size" -o /tmp "$SVG" >/dev/null 2>&1
  mv "/tmp/$(basename "$SVG").png" "$ICONSET/$outfile"
}

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$ICONSET"

echo "Rebuilt Resources/AppIcon.icns from $SVG"
