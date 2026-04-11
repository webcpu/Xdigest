#!/bin/bash
# Build + sign + notarize a distributable DMG for Xdigest.
#
# Notarization is ON by default -- a DMG that Gatekeeper rejects on first
# launch is not a distributable artifact, so shipping "signed but not
# notarized" makes no sense as a default. Use --no-notarize for fast local
# iteration (icon tweaks, smoke tests) when you don't need a shippable DMG.
#
# Usage:
#   ./scripts/make-dmg.sh                 # build, sign, notarize, staple
#   ./scripts/make-dmg.sh --no-notarize   # skip notarization (local dev only)
#
# Notarization requires a stored keychain profile. Create one once via:
#   xcrun notarytool store-credentials xdigest-notary \
#     --apple-id "you@example.com" \
#     --team-id  "NA5BE2D52P" \
#     --password "app-specific-password-from-appleid.apple.com"

set -euo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------

APP_NAME="Xdigest"
BUNDLE_ID="com.xdigest.app"
NOTARY_PROFILE="${XDIGEST_NOTARY_PROFILE:-xdigest-notary}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
SOURCE_INFO_PLIST="$PROJECT_DIR/Sources/XdigestApp/Info.plist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_ZIP="$DIST_DIR/$APP_NAME.zip"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

# Single source of truth: the committed Info.plist holds both values.
# `release.sh` updates this file; make-dmg.sh just reads it.
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$SOURCE_INFO_PLIST")
BUILD=$(plutil -extract CFBundleVersion raw -o - "$SOURCE_INFO_PLIST")

NOTARIZE=1

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log()    { printf '==> %s\n' "$*"; }
detail() { sed 's/^/    /'; }
die()    { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Phases -- each does ONE thing, no knowledge of other phases
# -----------------------------------------------------------------------------

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --no-notarize) NOTARIZE=0 ;;
            *)             die "Unknown flag: $arg" ;;
        esac
    done
}

build_release() {
    cd "$PROJECT_DIR"
    swift build -c release
    [ -x "$BUILD_DIR/$APP_NAME" ] || die "no executable at $BUILD_DIR/$APP_NAME"
    printf '    built %s\n' "$BUILD_DIR/$APP_NAME"
}

build_icon() {
    "$SCRIPT_DIR/make-icon.sh"
    [ -f "$PROJECT_DIR/Resources/Xdigest.icns" ] \
        || die "make-icon.sh did not produce Resources/Xdigest.icns"
}

write_info_plist() {
    cat << PLIST
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
    <string>$BUILD</string>
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
}

assemble_bundle() {
    rm -rf "$DIST_DIR"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    cp "$PROJECT_DIR/Resources/Xdigest.icns" "$APP_BUNDLE/Contents/Resources/Xdigest.icns"
    write_info_plist > "$APP_BUNDLE/Contents/Info.plist"
}

verify_bundle() {
    [ -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ] \
        || die "binary missing from bundle at Contents/MacOS/$APP_NAME"
    plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null \
        || die "invalid Info.plist"
    [ -f "$APP_BUNDLE/Contents/Resources/Xdigest.icns" ] \
        || die "icon missing from bundle at Contents/Resources/Xdigest.icns"
    printf '    binary + Info.plist + icon present\n'
}

sign_binary() {
    "$SCRIPT_DIR/sign.sh" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>&1 | detail
}

sign_bundle() {
    "$SCRIPT_DIR/sign.sh" "$APP_BUNDLE" 2>&1 | detail
}

verify_signature() {
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | detail
}

assess_gatekeeper() {
    if spctl --assess --verbose=2 "$APP_BUNDLE" 2>&1 | detail; then
        printf '    OK\n'
    else
        printf '    WARN: Gatekeeper rejected the app (expected if not yet notarized)\n'
    fi
}

build_dmg() {
    rm -f "$DIST_DIR"/*.dmg
    # create-dmg exits non-zero on some macOS versions even on success.
    create-dmg "$APP_BUNDLE" "$DIST_DIR" 2>&1 | detail || true

    local raw
    raw=$(ls "$DIST_DIR"/*.dmg 2>/dev/null | head -1)
    [ -n "$raw" ] || die "create-dmg produced no .dmg file in $DIST_DIR"
    mv "$raw" "$DMG_PATH"
    printf '    %s\n' "$DMG_PATH"
}

verify_dmg_signature() {
    codesign --verify --verbose=2 "$DMG_PATH" 2>&1 | detail
}

verify_dmg_integrity() {
    hdiutil verify "$DMG_PATH" 2>&1 | detail
}

require_notary_profile() {
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 && return 0
    cat >&2 <<EOF
ERROR: no notarytool keychain profile '$NOTARY_PROFILE' found.
Create one once with:

    xcrun notarytool store-credentials $NOTARY_PROFILE \\
      --apple-id YOUR_APPLE_ID \\
      --team-id  NA5BE2D52P \\
      --password APP_SPECIFIC_PASSWORD

EOF
    exit 1
}

zip_app() {
    # ditto preserves bundle structure and HFS+/APFS extended attributes,
    # which codesign and notarytool require. Plain `zip` strips xattrs.
    rm -f "$APP_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
    [ -f "$APP_ZIP" ] || die "ditto did not produce $APP_ZIP"
    printf '    %s\n' "$APP_ZIP"
}

submit_notarization() {
    local artifact=$1
    local log_file status
    log_file=$(mktemp)

    set +e
    xcrun notarytool submit "$artifact" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait 2>&1 | tee "$log_file" | detail
    status=${PIPESTATUS[0]}
    set -e

    if [ "$status" -ne 0 ]; then
        rm -f "$log_file"
        die "notarytool submit exited $status"
    fi
    if ! grep -q "status: Accepted" "$log_file"; then
        rm -f "$log_file"
        die "notarization did not return 'status: Accepted' (see log above)"
    fi
    rm -f "$log_file"
    printf '    notarization accepted\n'
}

staple_ticket() {
    xcrun stapler staple "$1" 2>&1 | detail
}

verify_stapled() {
    xcrun stapler validate "$1" 2>&1 | detail
}

assess_notarized_app() {
    spctl --assess --verbose=2 "$APP_BUNDLE" 2>&1 | detail
}

assess_notarized_dmg() {
    spctl --assess --type open --context context:primary-signature --verbose=2 \
        "$DMG_PATH" 2>&1 | detail
}

# -----------------------------------------------------------------------------
# Main -- composes the phases top-down like a Unix pipeline
# -----------------------------------------------------------------------------

main() {
    parse_args "$@"

    log "Building release";        build_release
    log "Building app icon";       build_icon
    log "Creating app bundle";     assemble_bundle
    log "Verifying bundle layout"; verify_bundle
    log "Signing binary";          sign_binary
    log "Signing bundle";          sign_bundle
    log "Verifying signature";     verify_signature
    log "Gatekeeper assessment";   assess_gatekeeper

    # Notarize the .app FIRST so the ticket gets stapled into the bundle
    # before it's wrapped in a DMG. Users who extract the .app from the DMG
    # (or receive it via any channel) then get an app that carries its own
    # ticket and launches offline on any machine.
    if [ "$NOTARIZE" = "1" ]; then
        require_notary_profile
        log "Zipping app for notarization";                  zip_app
        log "Submitting app for notarization (1-5 minutes)"
        submit_notarization "$APP_ZIP"
        log "Stapling notarization ticket to app";           staple_ticket "$APP_BUNDLE"
        log "Verifying stapled app";                         verify_stapled "$APP_BUNDLE"
        log "Gatekeeper assessment (notarized app)";         assess_notarized_app
        rm -f "$APP_ZIP"
    fi

    log "Creating DMG";            build_dmg
    log "Verifying DMG signature"; verify_dmg_signature
    log "Verifying DMG integrity"; verify_dmg_integrity

    # Notarize the DMG SECOND so downloaded DMGs also carry a stapled
    # ticket and Gatekeeper accepts them offline on first mount.
    if [ "$NOTARIZE" = "1" ]; then
        log "Submitting DMG for notarization (1-5 minutes)"
        submit_notarization "$DMG_PATH"
        log "Stapling notarization ticket to DMG";           staple_ticket "$DMG_PATH"
        log "Verifying stapled DMG";                         verify_stapled "$DMG_PATH"
        log "Gatekeeper assessment (notarized DMG)";         assess_notarized_dmg
    else
        log "Skipping notarization (--no-notarize set)"
        printf '    WARN: this DMG is NOT distributable -- Gatekeeper will reject it on first launch\n'
    fi

    log "Done"
    ls -lh "$DMG_PATH"
}

main "$@"
