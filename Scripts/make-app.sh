#!/bin/bash
# MiniDock 打包脚本：swift build -> 组装 .app（含程序生成图标）-> ad-hoc 签名
# 用法: ./Scripts/make-app.sh [debug|release] [版本号]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
APP_VERSION="${2:-1.0}"
APP_NAME="MiniDock"
BUILD_DIR="build"
APP_ROOT="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build ($CONFIGURATION)"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
swift build -c "$CONFIGURATION"

echo "==> 组装 $APP_ROOT"
rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_ROOT/Contents/MacOS/$APP_NAME"

echo "==> 生成应用图标"
ICON_PNG="$BUILD_DIR/appicon-1024.png"
if swift Scripts/gen-icon.swift "$ICON_PNG"; then
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256; do
        sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    sips -z 64 64 "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP_ROOT/Contents/Resources/AppIcon.icns"
else
    echo "    （图标生成失败，使用系统默认图标）"
fi

echo "==> 写入 Info.plist"
cat > "$APP_ROOT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>MiniDock</string>
    <key>CFBundleExecutable</key>
    <string>MiniDock</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.minidock.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MiniDock</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> 本地化资源（SwiftUI 从 Bundle.main 查找，SPM 的资源 bundle 需并入）"
if [ -d "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle/Contents/Resources" ]; then
    for lproj in "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle/Contents/Resources"/*.lproj; do
        [ -d "$lproj" ] && cp -R "$lproj" "$APP_ROOT/Contents/Resources/"
    done
fi

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP_ROOT"

echo ""
echo "✅ 完成: $APP_ROOT"
echo "   运行: open \"$APP_ROOT\""
