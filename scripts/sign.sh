#!/bin/bash
# Sign a binary or .app bundle with the Developer ID Application identity.
# Usage: ./scripts/sign.sh <path> [--no-timestamp]
#
# Using a stable Developer ID signature (instead of the default ad-hoc
# signature) keeps Little Snitch's code identity check happy across rebuilds.
#
# Secure timestamps are REQUIRED for notarization. They're on by default.
# Pass --no-timestamp to skip the timestamp server for faster local dev.

set -euo pipefail

TARGET="${1:-}"
SKIP_TIMESTAMP=0
for arg in "$@"; do
    [ "$arg" = "--no-timestamp" ] && SKIP_TIMESTAMP=1
done

if [ -z "$TARGET" ]; then
    echo "Usage: $0 <binary-or-app-bundle> [--no-timestamp]"
    exit 1
fi

if [ ! -e "$TARGET" ]; then
    echo "ERROR: $TARGET does not exist"
    exit 1
fi

# Auto-discover the Developer ID Application identity from the login
# keychain. Override with CODESIGN_IDENTITY=<SHA-1 or common name> if you
# have multiple Developer ID certificates.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')
fi
if [ -z "$IDENTITY" ]; then
    echo "ERROR: no 'Developer ID Application' identity found in keychain."
    echo "Set CODESIGN_IDENTITY or install a Developer ID certificate."
    exit 1
fi

# --force replaces any existing signature (ad-hoc from swift build).
# --options runtime enables the hardened runtime (required for notarization).
# Timestamp comes from Apple's timestamp server, required for notarization.
if [ "$SKIP_TIMESTAMP" = "1" ]; then
    codesign --force --sign "$IDENTITY" --timestamp=none --options runtime "$TARGET"
else
    codesign --force --sign "$IDENTITY" --timestamp --options runtime "$TARGET"
fi

echo "Signed: $TARGET"
codesign -dvv "$TARGET" 2>&1 | grep -E "Signature|TeamIdentifier|Authority"
