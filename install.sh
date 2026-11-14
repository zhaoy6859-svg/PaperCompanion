#!/bin/sh
# Build and install 论文伴侣 into ~/Applications, then launch it.
set -e
cd "$(dirname "$0")"

./build.sh

DEST="$HOME/Applications"
APP="论文伴侣.app"
mkdir -p "$DEST"

if pgrep -f "MacOS/PaperCompanion" >/dev/null 2>&1; then
  osascript -e 'tell application "论文伴侣" to quit' >/dev/null 2>&1 || pkill -f "MacOS/PaperCompanion" || true
  sleep 1
fi

rm -rf "$DEST/$APP"
cp -R "build/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true
codesign --force --sign - "$DEST/$APP" >/dev/null 2>&1 || true

# Let LaunchServices notice the new bundle.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST/$APP" >/dev/null 2>&1 || true

open "$DEST/$APP"
echo "✓ 已安装并启动：$DEST/$APP"
echo "  下一步：菜单「论文伴侣 → 设置…」可换 API Key / 模型，⌘O 打开论文"
