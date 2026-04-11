#!/bin/bash
# Build + sign Xdigest so Little Snitch is happy across rebuilds.
# Usage: ./scripts/build.sh [debug|release]

set -euo pipefail

CONFIG="${1:-debug}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"
swift build -c "$CONFIG"

BINARY="$PROJECT_DIR/.build/$CONFIG/Xdigest"
"$SCRIPT_DIR/sign.sh" "$BINARY"
