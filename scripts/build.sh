#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep every cache inside the project so the build also works in sandboxed
# environments (e.g. an editor/agent that only allows writes to the workspace).
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export TMPDIR="$PWD/.cache/tmp"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$TMPDIR"

swift build -c release --disable-sandbox --cache-path .cache/swiftpm --scratch-path .build

APP="build/NotchSlip.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/NotchSlip" "$APP/Contents/MacOS/NotchSlip"
cp Info.plist "$APP/Contents/Info.plist"
[ -f assets/AppIcon.icns ] && cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built: $(pwd)/$APP"