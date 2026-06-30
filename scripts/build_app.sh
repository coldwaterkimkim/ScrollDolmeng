#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXEC_NAME="ScrollDolmeng"
APP_NAME="울트라돌멩의원핑거스크롤"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXEC_NAME" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "$ROOT_DIR/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/AppResources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

xattr -cr "$APP_DIR" || true
xattr -d com.apple.FinderInfo "$APP_DIR" >/dev/null 2>&1 || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
# iCloud/File Provider folders can re-attach metadata after copy/sign.
# Strip it once more at the very end so Finder can launch the bundle cleanly.
xattr -cr "$APP_DIR" || true
xattr -d com.apple.FinderInfo "$APP_DIR" >/dev/null 2>&1 || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" >/dev/null 2>&1 || true

echo "$APP_DIR"
