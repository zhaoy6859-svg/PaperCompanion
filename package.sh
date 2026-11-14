#!/bin/sh
# Build 论文伴侣.app into a distributable DMG + ZIP under dist/.
set -e
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/论文伴侣.app/Contents/Info.plist)
APP="论文伴侣.app"
DIST="dist"
STAGE="build/dmg-stage"

rm -rf "$DIST" "$STAGE"
mkdir -p "$DIST" "$STAGE"

# --- staging folder shown in the DMG window
cp -R "build/$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<'TXT'
论文伴侣 Paper Companion 2.0

安装
  把「论文伴侣.app」拖到左边的 Applications 文件夹即可。

第一次打开
  1. 菜单「论文伴侣 → 设置…」粘贴 DeepSeek API Key（sk- 开头），点「测试连接」确认；
  2. ⌘O 或把 PDF 拖进窗口，右侧会出现译文与助手；
  3. 英文论文会自动用 XeLaTeX 排版本地译文（公式为 LaTeX 数学排版）。

关于签名
  这是本机构建的 ad-hoc 签名版本。若 macOS 提示「无法验证开发者」，
  在 Finder 里右键 App →「打开」，或执行：
      xattr -dr com.apple.quarantine /Applications/论文伴侣.app

系统要求
  macOS 13 或更新；译文排版需要本机安装含 XeLaTeX 的 MacTeX（可选）。
TXT

# --- DMG
hdiutil create -volname "论文伴侣 $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DIST/论文伴侣-$VERSION.dmg" >/dev/null

# --- ZIP (useful for direct download)
ditto -c -k --sequesterRsrc --keepParent "build/$APP" "$DIST/论文伴侣-$VERSION.zip"

# --- refresh LaunchServices so Finder shows the new icon
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "build/$APP" >/dev/null 2>&1 || true

echo "✓ dist/论文伴侣-$VERSION.dmg"
echo "✓ dist/论文伴侣-$VERSION.zip"
du -sh "$DIST"/* | sed 's/^/  /'
