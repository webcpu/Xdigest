#!/bin/bash
# Generate Xdigest.icns from xdigest.png (1024x1024 master).
# Uses sips to produce all required sizes, iconutil to pack .icns.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR/Resources/xdigest.png"
OUT="$PROJECT_DIR/Resources/Xdigest.icns"
TMP_ICONSET="$PROJECT_DIR/Resources/Xdigest.iconset"

if [ ! -f "$SRC" ]; then
    echo "Missing source icon: $SRC"
    exit 1
fi

rm -rf "$TMP_ICONSET"
mkdir -p "$TMP_ICONSET"

# Required sizes for a macOS .icns bundle
sips -z 16 16     "$SRC" --out "$TMP_ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$SRC" --out "$TMP_ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$SRC" --out "$TMP_ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$SRC" --out "$TMP_ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$SRC" --out "$TMP_ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$SRC" --out "$TMP_ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SRC" --out "$TMP_ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$SRC" --out "$TMP_ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SRC" --out "$TMP_ICONSET/icon_512x512.png"    >/dev/null
cp              "$SRC" "$TMP_ICONSET/icon_512x512@2x.png"

iconutil -c icns -o "$OUT" "$TMP_ICONSET"
rm -rf "$TMP_ICONSET"

echo "Built $OUT"
ls -lh "$OUT"
