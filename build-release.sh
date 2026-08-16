#!/bin/bash
# ====================================================================
# Quite Note 正式发布脚本（对外分发用）
# 流程: 构建 → Developer ID 签名 → 公证 .app → Staple → 打 DMG → 公证 DMG → Staple → 验证
#
# 前置条件（一次性配置，详见 AGENTS.md「开发者账号与打包发布」）:
#   1. 钥匙串中有 "Developer ID Application" 证书
#   2. 已执行 xcrun notarytool store-credentials quitenote-notary ...
#
# 用法: ./build-release.sh <版本号>
# 例如: ./build-release.sh 1.2.1
# ====================================================================
set -e

VERSION=${1:-}
if [ -z "$VERSION" ]; then
    echo "用法: ./build-release.sh <版本号>   例如: ./build-release.sh 1.2.1"
    exit 1
fi

TEAM_ID="B45VZCNYU3"
APPLE_ID="dyyz1993@icloud.com"
BUNDLE_ID="com.quitenote.app"
APP_NAME="Quite Note"
NOTARY_PROFILE="quitenote-notary"
APP_PATH="$APP_NAME.app"
DMG_FILE="QuiteNote-$VERSION.dmg"

echo "📦 发布版本: $VERSION"

# ------------------------------------------------------------------
# 1. 前置检查: Developer ID Application 证书
# ------------------------------------------------------------------
SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -z "$SIGN_IDENTITY" ]; then
    echo "❌ 钥匙串中没有 'Developer ID Application' 证书，无法对外分发"
    echo "   创建方法: Xcode → Settings → Accounts → 选中账号 → Manage Certificates… → ➕ → Developer ID Application"
    echo "   （或 developer.apple.com → Certificates → ➕，需要 Account Holder 权限）"
    echo "   创建后可用 security find-identity -v -p codesigning 验证"
    exit 1
fi
echo "✅ 签名证书: $SIGN_IDENTITY"

# ------------------------------------------------------------------
# 2. 前置检查: 公证凭据
# ------------------------------------------------------------------
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "❌ 未找到公证凭据 '$NOTARY_PROFILE'"
    echo "   先去 appleid.apple.com → 登录与安全 → App 专用密码 生成一个，然后执行:"
    echo "   xcrun notarytool store-credentials $NOTARY_PROFILE \\"
    echo "     --apple-id $APPLE_ID \\"
    echo "     --team-id $TEAM_ID \\"
    echo "     --password <应用专用密码>"
    exit 1
fi
echo "✅ 公证凭据: $NOTARY_PROFILE"

# ------------------------------------------------------------------
# 3. 构建并组装 .app（复用 build-app.sh，--no-launch 不自动启动）
# ------------------------------------------------------------------
echo ""
echo "🛠  构建 .app ..."
./build-app.sh --no-launch

# 覆写 Info.plist 中的版本号（build-app.sh 内置写死 1.0.0）
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP_PATH/Contents/Info.plist" >/dev/null
echo "✅ 版本号已写入: $VERSION"

# ------------------------------------------------------------------
# 4. Developer ID 正式签名（Hardened Runtime + 安全时间戳，公证必需）
# ------------------------------------------------------------------
echo ""
echo "🔐 Developer ID 签名 ..."
codesign --force --deep --options runtime --timestamp \
    --identifier "$BUNDLE_ID" \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"

codesign --verify --strict --verbose=1 "$APP_PATH"
echo "✅ 签名验证通过"

# ------------------------------------------------------------------
# 5. 公证 .app（压缩提交，通过后 Staple 到应用上）
# ------------------------------------------------------------------
echo ""
echo "📜 公证 .app（等待 Apple 审核，通常几分钟）..."
ZIP_FILE="QuiteNote-$VERSION-notary.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_FILE"
if ! xcrun notarytool submit "$ZIP_FILE" --keychain-profile "$NOTARY_PROFILE" --wait; then
    echo "❌ .app 公证失败，查看日志:"
    echo "   xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
    echo "   xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
    rm -f "$ZIP_FILE"
    exit 1
fi
rm -f "$ZIP_FILE"
xcrun stapler staple "$APP_PATH"
echo "✅ .app 公证并 Staple 完成"

# ------------------------------------------------------------------
# 6. 打 DMG（内含已公证并 Staple 的 .app）
# ------------------------------------------------------------------
echo ""
echo "💿 创建 DMG ..."
./create-dmg.sh "$VERSION"

# ------------------------------------------------------------------
# 7. 公证 DMG 并 Staple（保证离线环境首次打开也放行）
# ------------------------------------------------------------------
echo ""
echo "📜 公证 DMG ..."
if ! xcrun notarytool submit "$DMG_FILE" --keychain-profile "$NOTARY_PROFILE" --wait; then
    echo "❌ DMG 公证失败，查看日志:"
    echo "   xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
    echo "   xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
    exit 1
fi
xcrun stapler staple "$DMG_FILE"

# ------------------------------------------------------------------
# 8. 最终验证
# ------------------------------------------------------------------
echo ""
echo "🔍 最终验证 ..."
xcrun stapler validate "$DMG_FILE"
spctl -a -t open --context context:primary-signature -vv "$DMG_FILE"
spctl -a -t exec -vv "$APP_PATH"

echo ""
echo "🎉 发布包就绪: $DMG_FILE"
echo "   建议顺手打 tag:  git tag v$VERSION && git push origin v$VERSION"
