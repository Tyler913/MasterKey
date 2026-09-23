#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native -c release --product MasterKey
BUILD_DIR="$(swift build --build-system native -c release --show-bin-path)"
# Keep runnable build copies out of Launch Services and application search results.
mkdir -p "$PWD/.build/package.noindex" "$PWD/dist"
PACKAGE_STAGE="$(mktemp -d "$PWD/.build/package.noindex/XXXXXXXX")"
trap 'rm -rf "$PACKAGE_STAGE"' EXIT
APP_DIR="$PACKAGE_STAGE/MasterKey.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/MasterKey" "$APP_DIR/Contents/MacOS/MasterKey"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
for localization in Resources/*.lproj; do
    ditto "$localization" "$APP_DIR/Contents/Resources/$(basename "$localization")"
done
codesign --force --sign - --identifier local.masterkey.bridge "$APP_DIR"
codesign --verify --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$PACKAGE_STAGE/MasterKey.zip"
mv -f "$PACKAGE_STAGE/MasterKey.zip" "$PWD/dist/MasterKey.zip"
printf 'Built: %s\n' "$PWD/dist/MasterKey.zip"
