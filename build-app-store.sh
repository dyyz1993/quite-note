#!/bin/bash
# ====================================================================
# Quite Note Mac App Store 发布脚本
# 流程：App Store 沙盒构建 → provisioning profile 嵌入 →
#       Apple Distribution 签名 → Mac Installer Distribution 打包 → 验证
#
# 用法：
#   ./build-app-store.sh 1.0.0
#   ./build-app-store.sh 1.0.0 --upload
#
# 上传前需要在环境变量中提供：
#   ASC_KEY_ID / ASC_ISSUER_ID
#   以及标准路径：~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
# ====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="${1:-}"
UPLOAD=false
for arg in "$@"; do
    if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then
        echo "用法: ./build-app-store.sh <版本号> [--upload]"
        echo "环境变量：APP_STORE_PROVISIONING_PROFILE、BUILD_NUMBER"
        echo "上传变量：ASC_KEY_ID、ASC_ISSUER_ID"
        exit 0
    fi
    if [ "$arg" = "--upload" ]; then
        UPLOAD=true
    fi
done

if [ -z "$VERSION" ] || [ "$VERSION" = "--upload" ]; then
    echo "用法: ./build-app-store.sh <版本号> [--upload]"
    echo "例如: ./build-app-store.sh 1.0.0"
    exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "❌ 版本号必须是数字格式，例如 1.0.0"
    exit 1
fi

TEAM_ID="B45VZCNYU3"
BUNDLE_ID="com.quitenote.app"
APP_NAME="Quite Note"
APP_PATH="$APP_NAME.app"
PKG_FILE="QuiteNote-$VERSION-macOS.pkg"
ENTITLEMENTS="$SCRIPT_DIR/QuiteNote-AppStore.entitlements"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "❌ 缺少 App Store entitlements: $ENTITLEMENTS"
    exit 1
fi

USER_HOME="$(dscl . -read "/Users/${USER:?}" NFSHomeDirectory | awk '{print $2}')"
PROFILES_DIR="$USER_HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_PATH="${APP_STORE_PROVISIONING_PROFILE:-}"

find_identity() {
    local pattern="$1"
    security find-identity -v -p codesigning \
        | awk -F'"' -v pattern="$pattern" '$2 ~ pattern { print $2; exit }'
}

find_installer_identity() {
    security find-identity -v -p basic \
        | awk -F'"' '/Mac Installer Distribution|3rd Party Mac Developer Installer/ { print $2; exit }'
}

if [ -z "${APP_SIGN_IDENTITY:-}" ]; then
    APP_SIGN_IDENTITY="$(find_identity 'Mac App Distribution|Apple Distribution|3rd Party Mac Developer Application' || true)"
fi
if [ -z "$APP_SIGN_IDENTITY" ]; then
    echo "❌ 未找到 App Store 应用签名证书。"
    echo "   需要 Mac App Distribution（部分系统显示为 Apple Distribution 或旧名称 3rd Party Mac Developer Application）证书。"
    echo "   当前可见证书："
    security find-identity -v -p codesigning || true
    exit 2
fi

if [ -z "${INSTALLER_SIGN_IDENTITY:-}" ]; then
    INSTALLER_SIGN_IDENTITY="$(find_installer_identity || true)"
fi
if [ -z "$INSTALLER_SIGN_IDENTITY" ]; then
    echo "❌ 未找到 Mac App Store 安装包签名证书。"
    echo "   需要 Mac Installer Distribution（旧名称：3rd Party Mac Developer Installer）证书。"
    echo "   该证书用于 productbuild，不是 Developer ID Installer。"
    exit 2
fi

profile_app_id() {
    local profile="$1"
    local decoded
    decoded="$(security cms -D -i "$profile" 2>/dev/null || true)"
    [ -n "$decoded" ] || return 0

    # Apple profiles may expose this entitlement under either the legacy
    # application-identifier key or the current com.apple-prefixed key.
    local entitlements
    entitlements="$(plutil -extract Entitlements xml1 -o - - <<<"$decoded" 2>/dev/null || true)"
    [ -n "$entitlements" ] || return 0
    plutil -p - <<<"$entitlements" \
        | sed -n \
            -e 's/.*"application-identifier" => "\([^"]*\)"/\1/p' \
            -e 's/.*"com\.apple\.application-identifier" => "\([^"]*\)"/\1/p' \
        | head -n 1
}

profile_name() {
    local profile="$1"
    security cms -D -i "$profile" 2>/dev/null \
        | plutil -extract Name raw -o - - 2>/dev/null \
        || true
}

if [ -z "$PROFILE_PATH" ]; then
    if [ -d "$PROFILES_DIR" ]; then
        while IFS= read -r candidate; do
            [ -f "$candidate" ] || continue
            candidate_app_id="$(profile_app_id "$candidate")"
            if [ "$candidate_app_id" = "$TEAM_ID.$BUNDLE_ID" ]; then
                PROFILE_PATH="$candidate"
                break
            fi
        done < <(find "$PROFILES_DIR" -type f -name '*.provisionprofile' -print 2>/dev/null)
    fi
fi

if [ -z "$PROFILE_PATH" ] || [ ! -f "$PROFILE_PATH" ]; then
    echo "❌ 未找到匹配 $BUNDLE_ID 的 App Store provisioning profile。"
    echo "   可通过 APP_STORE_PROVISIONING_PROFILE=/path/to/profile.provisionprofile 指定。"
    echo "   当前查找目录：$PROFILES_DIR"
    exit 2
fi

PROFILE_APP_ID="$(profile_app_id "$PROFILE_PATH")"
if [ "$PROFILE_APP_ID" != "$TEAM_ID.$BUNDLE_ID" ]; then
    echo "❌ provisioning profile 的 application-identifier 不匹配：$PROFILE_APP_ID"
    echo "   期望：$TEAM_ID.$BUNDLE_ID"
    exit 2
fi

echo "📦 App Store 构建：$VERSION"
echo "✅ 应用证书：$APP_SIGN_IDENTITY"
echo "✅ 安装包证书：$INSTALLER_SIGN_IDENTITY"
echo "✅ provisioning profile：$(profile_name "$PROFILE_PATH")"

echo ""
echo "🛠 构建 App Store 沙盒应用..."
./build-app.sh --app-store --no-launch

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$APP_PATH/Contents/Info.plist" >/dev/null

cp "$PROFILE_PATH" "$APP_PATH/Contents/embedded.provisionprofile"

# Files downloaded from the web or copied from Downloads may carry the
# com.apple.quarantine extended attribute. Apple rejects that attribute in
# Mac App Store packages (including the embedded provisioning profile), so
# clear attributes from the app bundle before signing and packaging.
if command -v xattr >/dev/null 2>&1; then
    echo "🧹 清理应用包扩展属性..."
    # Some bundled resources are read-only after SwiftPM copies them. The
    # staging app is a generated artifact, so make it writable for this
    # cleanup only; do not touch the source tree.
    chmod -R u+rwX "$APP_PATH"
    xattr -cr "$APP_PATH" 2>/dev/null || true
    if find "$APP_PATH" -type f -exec xattr -p com.apple.quarantine {} \; 2>/dev/null | grep -q .; then
        echo "❌ 应用包仍包含 com.apple.quarantine 属性"
        exit 3
    fi
fi

echo "🔐 签名应用..."
codesign --force --deep --options runtime --timestamp \
    --identifier "$BUNDLE_ID" \
    --entitlements "$ENTITLEMENTS" \
    --sign "$APP_SIGN_IDENTITY" \
    "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --entitlements :- "$APP_PATH" 2>/dev/null \
    | grep -q 'com.apple.security.app-sandbox' \
    || { echo "❌ 最终应用未带 App Sandbox entitlement"; exit 3; }

echo "📦 创建 Mac App Store .pkg..."
rm -f "$PKG_FILE"
productbuild \
    --component "$APP_PATH" /Applications \
    --sign "$INSTALLER_SIGN_IDENTITY" \
    "$PKG_FILE"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PKG_FILE" 2>/dev/null || true
fi

pkgutil --check-signature "$PKG_FILE"
echo "✅ App Store 安装包已生成：$PKG_FILE"

if [ "$UPLOAD" = true ]; then
    ASC_KEY_ID="${ASC_KEY_ID:-}"
    ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
    KEY_PATH="$USER_HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

    if [ -z "$ASC_KEY_ID" ] || [ -z "$ASC_ISSUER_ID" ] || [ ! -f "$KEY_PATH" ]; then
        echo "❌ 上传所需的 App Store Connect API Key 不完整。"
        echo "   需要 ASC_KEY_ID、ASC_ISSUER_ID，以及可读的 .p8 文件。"
        echo "   当前查找路径：$KEY_PATH"
        exit 4
    fi

    if xcrun altool --help >/dev/null 2>&1; then
        echo "🚚 使用 Xcode altool 上传到 App Store Connect..."
        xcrun altool \
            --upload-package "$PKG_FILE" \
            --api-key "$ASC_KEY_ID" \
            --api-issuer "$ASC_ISSUER_ID"
    else
        echo "🚚 使用 Transporter 上传到 App Store Connect..."
        xcrun iTMSTransporter \
            -m upload \
            -assetFile "$PKG_FILE" \
            -apiKey "$ASC_KEY_ID" \
            -apiIssuer "$ASC_ISSUER_ID"
    fi
    echo "✅ 已提交上传，后续请在 App Store Connect 的构建页面等待处理完成。"
fi
