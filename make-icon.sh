#!/bin/bash
# Builds build/AppIcon.icns from images/logo.png.
# Regenerated on every build so the icon can't drift from the artwork.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$ROOT/images/logo.png"
WORK="$ROOT/build/AppIcon.iconset"
ICNS="$ROOT/build/AppIcon.icns"

[ -f "$SOURCE" ] || { echo "missing $SOURCE" >&2; exit 1; }

rm -rf "$WORK" "$ICNS"
mkdir -p "$WORK"

# Pad to a square before scaling, so the artwork isn't stretched. sips pads
# transparently, which is what we want for the corners.
width=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/{print $2}')
height=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/{print $2}')
side=$(( width > height ? width : height ))

square="$ROOT/build/icon-square.png"
sips -p "$side" "$side" "$SOURCE" --out "$square" >/dev/null
sips -z 1024 1024 "$square" --out "$square" >/dev/null

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$square" --out "$WORK/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$square" --out "$WORK/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$WORK" -o "$ICNS"
rm -rf "$WORK" "$square"

echo "Icon: $ICNS"
