#!/bin/bash
# Build, sign, restart, and verify Xdigest in one command.
# Use this instead of remembering the individual steps.
#
# Usage: ./scripts/dev.sh           # full cycle
#        ./scripts/dev.sh --test    # also run tests first
#        ./scripts/dev.sh --release # build release instead of debug

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="debug"
RUN_TESTS=0
PORT=8408

for arg in "$@"; do
    case "$arg" in
        --release) CONFIG="release" ;;
        --test)    RUN_TESTS=1 ;;
        *)         echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

BINARY="$PROJECT_DIR/.build/$CONFIG/Xdigest"

cd "$PROJECT_DIR"

if [ "$RUN_TESTS" = "1" ]; then
    echo "==> Running tests"
    swift test 2>&1 | grep -E "Test run|failed|error:" | tail -5
fi

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" 2>&1 | grep -E "error:|warning:|Build complete" | tail -5

echo "==> Signing"
"$SCRIPT_DIR/sign.sh" "$BINARY" 2>&1 | tail -1

echo "==> Stopping old process"
pkill -f "Xdigest" 2>/dev/null || true

# Wait for port to be released
for i in 1 2 3 4 5; do
    if ! lsof -i :"$PORT" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

echo "==> Starting new process"
"$BINARY" 2>/tmp/xdigest-err.txt &
APP_PID=$!

# Wait for server to come up (up to 5 seconds)
for i in $(seq 1 25); do
    if curl -sf -o /dev/null "http://localhost:$PORT/api/mtime"; then
        break
    fi
    sleep 0.2
done

echo "==> Verifying"
RESPONSE=$(curl -s "http://localhost:$PORT/api/mtime" || true)
if [ -z "$RESPONSE" ]; then
    echo "FAIL: server did not respond on port $PORT"
    echo "--- stderr log ---"
    cat /tmp/xdigest-err.txt
    exit 1
fi

VERSION=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'v{d[\"version\"]} mtime={d[\"mtime\"]:.0f} posts={d[\"postCount\"]}')" 2>/dev/null || echo "?")
INSTANCE=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['instanceId'][:8])" 2>/dev/null || echo "?")

echo "==> Running: pid=$APP_PID instance=$INSTANCE $VERSION"
