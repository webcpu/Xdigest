#!/bin/bash
set -euo pipefail

APP_NAME="Xdigest"
BUNDLE_ID="com.xdigest.app"
VERSION="0.1.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "Building release..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing app bundle..."
"$SCRIPT_DIR/sign.sh" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
"$SCRIPT_DIR/sign.sh" "$APP_BUNDLE"

echo "Creating DMG..."
rm -f "$DIST_DIR/$APP_NAME.dmg"
create-dmg "$APP_BUNDLE" "$DIST_DIR" || true
# create-dmg exits non-zero even on success if code signing is skipped

DMG_FILE=$(ls "$DIST_DIR"/*.dmg 2>/dev/null | head -1)
if [ -n "$DMG_FILE" ]; then
    # Rename to clean name
    mv "$DMG_FILE" "$DIST_DIR/$APP_NAME-$VERSION.dmg"
    echo "Done: $DIST_DIR/$APP_NAME-$VERSION.dmg"
    ls -lh "$DIST_DIR/$APP_NAME-$VERSION.dmg"
else
    echo "ERROR: DMG was not created"
    exit 1
fi
