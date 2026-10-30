#!/bin/bash
# 打包 MiniDock DMG 安装包（拖入 Applications 即安装）
# 用法: ./Scripts/make-dmg.sh [版本号，默认 1.12]
# 流程：构建 App → 读写 DMG → Finder 布局（App 左 / Applications 右）→ 压缩为分发 DMG
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.12}"
APP_NAME="MiniDock"
APP="build/${APP_NAME}.app"
DMG_RW="build/${APP_NAME}-rw.dmg"
DMG="build/${APP_NAME}-${VERSION}.dmg"
STAGING="build/dmg-staging"
VOL_NAME="${APP_NAME}"
MOUNT="/Volumes/${VOL_NAME}"

echo "==> 1/5 构建 App（版本 ${VERSION}）"
./Scripts/make-app.sh release "${VERSION}" >/dev/null

echo "==> 2/5 准备内容（App + Applications 链接）"
rm -rf "${STAGING}" "${DMG}" "${DMG_RW}"
mkdir -p "${STAGING}"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

echo "==> 3/5 生成读写 DMG"
hdiutil create -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" -ov -format UDRW \
    "${DMG_RW}" >/dev/null 2>&1

echo "==> 4/5 Finder 布局"
hdiutil attach "${DMG_RW}" -mountpoint "${MOUNT}" -quiet
osascript <<EOF
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 420}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set position of item "${APP_NAME}" of container window to {120, 100}
        set position of item "Applications" of container window to {360, 100}
        update items without asking
        close
    end tell
end tell
EOF
sync
hdiutil detach "${MOUNT}" -quiet

echo "==> 5/5 压缩为分发 DMG"
hdiutil convert "${DMG_RW}" -format UDZO -o "${DMG}" >/dev/null
rm -rf "${DMG_RW}" "${STAGING}"

SIZE=$(du -h "${DMG}" | cut -f1)
echo ""
echo "✅ 安装包: ${DMG} (${SIZE})"
echo "   双击挂载后，把 MiniDock 拖到 Applications 文件夹即完成安装"
