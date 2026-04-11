#!/bin/bash
# Build + sign + (optionally notarize) a release DMG for Xdigest.
#
# Usage:
#   ./scripts/make-dmg.sh              # build, sign, verify
#   ./scripts/make-dmg.sh --notarize   # also notarize + staple for distribution
#
# Notarization requires a stored keychain profile. Create one once via:
#   xcrun notarytool store-credentials xdigest-notary \
#     --apple-id "you@example.com" \
#     --team-id  "NA5BE2D52P" \
#     --password "app-specific-password-from-appleid.apple.com"

set -euo pipefail

APP_NAME="Xdigest"
BUNDLE_ID="com.xdigest.app"
VERSION="0.1.0"
# Keychain profile used for xcrun notarytool. Override via env if needed.
NOTARY_PROFILE="${XDIGEST_NOTARY_PROFILE:-xdigest-notary}"

NOTARIZE=0
for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=1 ;;
        *)          echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# -----------------------------------------------------------------------------
# 1. Build + icon
# -----------------------------------------------------------------------------

echo "==> Building release"
cd "$PROJECT_DIR"
swift build -c release

echo "==> Building app icon"
"$SCRIPT_DIR/make-icon.sh"

# -----------------------------------------------------------------------------
# 2. Assemble .app bundle
# -----------------------------------------------------------------------------

echo "==> Creating app bundle"
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Xdigest.icns" "$APP_BUNDLE/Contents/Resources/Xdigest.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>Xdigest</string>
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

# -----------------------------------------------------------------------------
# 3. Sign
# -----------------------------------------------------------------------------

echo "==> Signing"
"$SCRIPT_DIR/sign.sh" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null
"$SCRIPT_DIR/sign.sh" "$APP_BUNDLE" >/dev/null

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
# Expect: valid on disk + satisfies its Designated Requirement

echo "==> Gatekeeper assessment"
if spctl --assess --verbose=2 "$APP_BUNDLE" 2>&1 | sed 's/^/    /'; then
    echo "    OK"
else
    echo "    WARN: Gatekeeper rejected the app (expected if not yet notarized)"
fi

# -----------------------------------------------------------------------------
# 4. Build DMG
# -----------------------------------------------------------------------------

echo "==> Creating DMG"
rm -f "$DIST_DIR"/*.dmg
create-dmg "$APP_BUNDLE" "$DIST_DIR" || true
# create-dmg exits non-zero on some macOS versions even on success

RAW_DMG=$(ls "$DIST_DIR"/*.dmg 2>/dev/null | head -1)
if [ -z "$RAW_DMG" ]; then
    echo "ERROR: DMG was not created"
    exit 1
fi
mv "$RAW_DMG" "$DMG_PATH"
echo "    $DMG_PATH"

# -----------------------------------------------------------------------------
# 5. Notarize + staple (optional)
# -----------------------------------------------------------------------------

if [ "$NOTARIZE" = "1" ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "ERROR: no notarytool keychain profile '$NOTARY_PROFILE' found."
        echo "Create one once with:"
        echo ""
        echo "    xcrun notarytool store-credentials $NOTARY_PROFILE \\"
        echo "      --apple-id YOUR_APPLE_ID \\"
        echo "      --team-id  NA5BE2D52P \\"
        echo "      --password APP_SPECIFIC_PASSWORD"
        echo ""
        exit 1
    fi

    echo "==> Submitting DMG for notarization (this takes 1-5 minutes)"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait 2>&1 | sed 's/^/    /'

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$DMG_PATH" 2>&1 | sed 's/^/    /'

    echo "==> Verifying stapled DMG"
    xcrun stapler validate "$DMG_PATH" 2>&1 | sed 's/^/    /'
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" 2>&1 | sed 's/^/    /'
else
    echo "==> Skipping notarization (use --notarize to enable)"
    echo "    Downloaded DMGs will show a Gatekeeper warning on first launch."
fi

# -----------------------------------------------------------------------------
# 6. Done
# -----------------------------------------------------------------------------

echo "==> Done"
ls -lh "$DMG_PATH"
