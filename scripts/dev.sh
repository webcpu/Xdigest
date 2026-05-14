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
VERIFY_ATTEMPTS=150

for arg in "$@"; do
    case "$arg" in
        --release) CONFIG="release" ;;
        --test)    RUN_TESTS=1 ;;
        *)         echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

BINARY="$PROJECT_DIR/.build/$CONFIG/Xdigest"
SOURCE_INFO_PLIST="$PROJECT_DIR/Sources/XdigestApp/Info.plist"

cd "$PROJECT_DIR"

if [ "$RUN_TESTS" = "1" ]; then
    echo "==> Running tests"
    swift test 2>&1 | grep -E "Test run|failed|error:" | tail -5
fi

if [ -x "$BINARY" ] && [ "$SOURCE_INFO_PLIST" -nt "$BINARY" ]; then
    echo "==> Info.plist changed since last link; cleaning build artifacts"
    # Package.swift injects Info.plist via linker flags, but SwiftPM does
    # not track that excluded plist as a build input. Force a relink when
    # the plist is newer so the embedded version metadata stays correct.
    swift package clean
fi

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" 2>&1 | grep -E "error:|warning:|Build complete" | tail -5

echo "==> Signing"
# Sparkle.framework ships with Sparkle's own Team ID. Re-sign it with
# our Developer ID so macOS allows the signed binary to load it.
# --deep is deprecated for production (make-dmg.sh signs innermost-first)
# but fine for dev iteration speed.
codesign --force --deep --sign "$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')" \
    --options runtime --timestamp=none \
    "$PROJECT_DIR/.build/$CONFIG/Sparkle.framework" 2>/dev/null
"$SCRIPT_DIR/sign.sh" "$BINARY" --no-timestamp 2>&1 | tail -1

echo "==> Updating firewall rule"
# Each rebuild changes the binary's CDHash. macOS firewall silently blocks
# the new binary even though the path and signing identity are unchanged.
# Re-add the binary so the firewall learns the new hash.
/usr/libexec/ApplicationFirewall/socketfilterfw --remove "$BINARY" 2>/dev/null || true
/usr/libexec/ApplicationFirewall/socketfilterfw --add "$BINARY" 2>/dev/null
/usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$BINARY" 2>/dev/null

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
STDOUT_LOG="/tmp/xdigest-out.txt"
STDERR_LOG="/tmp/xdigest-err.txt"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"
APP_PID=$(python3 - "$BINARY" "$STDOUT_LOG" "$STDERR_LOG" <<'PY'
import subprocess
import sys

binary, stdout_path, stderr_path = sys.argv[1:]
with open(stdout_path, "wb") as stdout, open(stderr_path, "wb") as stderr:
    process = subprocess.Popen(
        [binary],
        stdin=subprocess.DEVNULL,
        stdout=stdout,
        stderr=stderr,
        start_new_session=True,
    )
print(process.pid)
PY
)

# Wait for server to come up (up to 30 seconds). App launch runs setup
# probes before binding the server, and those probes may call external
# CLIs such as bird and Claude.
for i in $(seq 1 "$VERIFY_ATTEMPTS"); do
    if curl -sf -o /dev/null "http://localhost:$PORT/api/mtime"; then
        break
    fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "FAIL: app exited before server responded on port $PORT"
        echo "--- stderr log ---"
        tail -120 "$STDERR_LOG"
        echo "--- stdout log ---"
        tail -120 "$STDOUT_LOG"
        exit 1
    fi
    sleep 0.2
done

echo "==> Verifying"
RESPONSE=$(curl -s "http://localhost:$PORT/api/mtime" || true)
if [ -z "$RESPONSE" ]; then
    echo "FAIL: server did not respond on port $PORT after 30s"
    if kill -0 "$APP_PID" 2>/dev/null; then
        echo "App process is still running (pid=$APP_PID). Check for a setup window or a slow startup probe."
    fi
    echo "--- stderr log ---"
    tail -120 "$STDERR_LOG"
    echo "--- stdout log ---"
    tail -120 "$STDOUT_LOG"
    exit 1
fi

VERSION=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'v{d[\"version\"]} mtime={d[\"mtime\"]:.0f} posts={d[\"postCount\"]}')" 2>/dev/null || echo "?")
INSTANCE=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['instanceId'][:8])" 2>/dev/null || echo "?")

echo "==> Running: pid=$APP_PID instance=$INSTANCE $VERSION"
