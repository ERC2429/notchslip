#!/bin/bash
# Builds a universal (arm64 + x86_64) app bundle plus zip and dmg for another Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export TMPDIR="$PWD/.cache/tmp"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$TMPDIR" .cache/dist dist

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
SDK=$(xcrun --show-sdk-path)
SOURCES=(Sources/NotchSlip/*.swift)

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -sdk "$SDK" -target "$arch-apple-macosx14.0" \
        -o ".cache/dist/NotchSlip-$arch" "${SOURCES[@]}" \
        -framework AppKit -framework Carbon
done

APP="dist/NotchSlip.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/NotchSlip" \
    .cache/dist/NotchSlip-arm64 .cache/dist/NotchSlip-x86_64
cp Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

STAGE="dist/stage-$VERSION"
ZIP="dist/NotchSlip-$VERSION.zip"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
[ -f docs/INSTALL.md ] && cp docs/INSTALL.md "$STAGE/"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --noacl "$STAGE/" "$ZIP"
rm -rf "$STAGE"

echo "app: $APP"
echo "zip: $ZIP"

DMG="dist/NotchSlip-$VERSION.dmg"
if rm -rf dist/dmg-staging && mkdir -p dist/dmg-staging; then
    cp -R "$APP" dist/dmg-staging/
    ln -s /Applications dist/dmg-staging/Applications
    if hdiutil create -quiet -volname "NotchSlip" -srcfolder dist/dmg-staging \
        -ov -format UDZO "$DMG" 2>/dev/null; then
        echo "dmg: $DMG"
    else
        echo "dmg: skipped (hdiutil unavailable in this environment)"
    fi
    rm -rf dist/dmg-staging
fi
lipo -info "$APP/Contents/MacOS/NotchSlip"
codesign --verify --deep --strict --verbose=1 "$APP"
