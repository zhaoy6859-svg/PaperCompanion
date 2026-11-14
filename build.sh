#!/bin/sh
# Build 论文伴侣.app from Sources/*.swift — no Xcode project required.
set -e
cd "$(dirname "$0")"

APP_NAME="论文伴侣"
BUNDLE="build/$APP_NAME.app"
BIN="build/PaperCompanion"

mkdir -p build/mc "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "▸ compiling"
swiftc -O \
  -target arm64-apple-macos13.0 \
  -module-cache-path build/mc \
  -framework WebKit -framework AppKit -framework Carbon -framework PDFKit -framework Security -framework ServiceManagement \
  Sources/*.swift \
  -o "$BIN"

echo "▸ assembling bundle"
cp "$BIN" "$BUNDLE/Contents/MacOS/PaperCompanion"
cp Info.plist "$BUNDLE/Contents/Info.plist"
if [ -d Resources ]; then ditto Resources "$BUNDLE/Contents/Resources"; fi
if [ -f icon.icns ]; then cp icon.icns "$BUNDLE/Contents/Resources/icon.icns"; fi

echo "▸ signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null 2>&1 || true

echo "✓ $BUNDLE"
