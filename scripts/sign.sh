#!/bin/bash
# Sign a binary or .app bundle with the Developer ID Application identity.
# Usage: ./scripts/sign.sh <path>
#
# Using a stable Developer ID signature (instead of the default ad-hoc
# signature) keeps Little Snitch's code identity check happy across rebuilds.

set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    echo "Usage: $0 <binary-or-app-bundle>"
    exit 1
fi

if [ ! -e "$TARGET" ]; then
    echo "ERROR: $TARGET does not exist"
    exit 1
fi

IDENTITY="Developer ID Application: Liang Yuan (NA5BE2D52P)"

# --force replaces any existing signature (ad-hoc from swift build).
# --timestamp=none skips the timestamp server (faster for local dev).
# --options runtime enables the hardened runtime (required for notarization).
codesign --force --sign "$IDENTITY" --timestamp=none --options runtime "$TARGET"

echo "Signed: $TARGET"
codesign -dvv "$TARGET" 2>&1 | grep -E "Signature|TeamIdentifier|Authority"
