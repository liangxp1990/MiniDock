#!/bin/bash
# MiniDock 一键发版：DMG → EdDSA 签名 → appcast → tag → GitHub Release
# 用法: ./Scripts/release.sh <版本号>  例: ./Scripts/release.sh 2.1
# 依赖: gh(已登录)、Sparkle 工具(/tmp/sparkle/Sparkle-new/bin)、钥匙串中的 EdDSA 私钥
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: ./Scripts/release.sh <版本号>}"
TAG="v${VERSION}"
SPARKLE_BIN="${SPARKLE_BIN:-/tmp/sparkle/Sparkle-new/bin}"
DMG="build/MiniDock-${VERSION}.dmg"

echo "==> 1/5 打包 DMG ${VERSION}"
./Scripts/make-dmg.sh "${VERSION}" >/dev/null

echo "==> 2/5 EdDSA 签名更新包"
SIG=$("$SPARKLE_BIN/sign_update" "$DMG")
echo "    ${SIG}"

echo "==> 3/5 生成 appcast.xml"
DMG_SIZE=$(stat -f %z "$DMG")
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
cat > appcast.xml <<XML
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>MiniDock</title>
        <link>https://raw.githubusercontent.com/liangxp1990/MiniDock/main/appcast.xml</link>
        <description>MiniDock 更新日志</description>
        <item>
            <title>MiniDock ${VERSION}</title>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure
                url="https://github.com/liangxp1990/MiniDock/releases/download/${TAG}/MiniDock-${VERSION}.dmg"
                sparkle:edSignature="${SIG#sparkle:edSignature=}"
                length="${DMG_SIZE}"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
XML

echo "==> 4/5 提交并打 tag"
git add appcast.xml
git -c user.name="liangxp1990" -c user.email="liangxp1990@users.noreply.github.com" \
    commit -m "release: ${TAG}" >/dev/null || true
git tag -f "${TAG}" >/dev/null
git push origin main --tags --force 2>/dev/null || git push origin main --tags

echo "==> 5/5 发布 GitHub Release"
gh release create "${TAG}" "$DMG" \
    --title "MiniDock ${TAG}" \
    --notes "MiniDock ${VERSION} —— 更新说明见 appcast / README。" \
    2>/dev/null || gh release upload "${TAG}" "$DMG" --clobber

echo ""
echo "✅ ${TAG} 发布完成（含自动更新签名）"
