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
        | awk -F'"' -v pattern="$pattern" '$2 ~ pattern { print $1; exit }' \
        | awk '{ print $2 }'
}

find_installer_identity() {
    security find-identity -v -p basic \
        | awk -F'"' '/Mac Installer Distribution|3rd Party Mac Developer Installer/ { print $1; exit }' \
        | awk '{ print $2 }'
}

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

profile_signing_identity() {
    local profile="$1"
    local certificate_fingerprint
    certificate_fingerprint="$(security cms -D -i "$profile" 2>/dev/null \
        | plutil -extract DeveloperCertificates.0 raw -o - - 2>/dev/null \
        | base64 -D \
        | openssl x509 -inform DER -noout -fingerprint -sha1 2>/dev/null \
        | sed 's/.*=//' \
        | tr -d ':')"
    [ -n "$certificate_fingerprint" ] || return 0

    security find-identity -v -p codesigning \
        | awk -F'"' -v fingerprint="$certificate_fingerprint" '$1 ~ fingerprint { print $1; exit }' \
        | awk '{ print $2 }'
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

# The embedded App Store profile authorizes a specific distribution certificate.
# Keychains may have multiple certificates with the same display name, so always
# resolve the exact SHA-1 identity from the profile instead of selecting by name.
PROFILE_SIGN_IDENTITY="$(profile_signing_identity "$PROFILE_PATH")"
if [ -z "$PROFILE_SIGN_IDENTITY" ]; then
    echo "❌ provisioning profile 中的应用签名证书未安装，或无法解析。"
    echo "   profile：$(profile_name "$PROFILE_PATH")"
    exit 2
fi
if [ -n "${APP_SIGN_IDENTITY:-}" ] && [ "$APP_SIGN_IDENTITY" != "$PROFILE_SIGN_IDENTITY" ]; then
    echo "❌ APP_SIGN_IDENTITY 与 provisioning profile 中的签名证书不一致。"
    echo "   请移除 APP_SIGN_IDENTITY，让脚本自动匹配 profile。"
    exit 2
fi
APP_SIGN_IDENTITY="$PROFILE_SIGN_IDENTITY"

echo "📦 App Store 构建：$VERSION"
echo "✅ 应用证书：$APP_SIGN_IDENTITY"
echo "✅ 安装包证书：$INSTALLER_SIGN_IDENTITY"
echo "✅ provisioning profile：$(profile_name "$PROFILE_PATH")"

echo ""
echo "🛠 构建 App Store 沙盒应用..."
APP_SIGN_IDENTITY="$APP_SIGN_IDENTITY" ./build-app.sh --app-store --no-launch

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$APP_PATH/Contents/Info.plist" >/dev/null

if [ "$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)" != "false" ]; then
    echo "❌ Info.plist 缺少 ITSAppUsesNonExemptEncryption=false，无法自动完成出口合规声明。"
    exit 3
fi

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

# 用户主动选择的导出目录由 user-selected + security-scoped bookmark 授权；
# 不需要也不得重新加入全局 Downloads 文件夹读写权限。必须审计最终签名产物，
# 而不是只检查源 entitlements 文件，因为审核和上传看到的是这里的结果。
SIGNED_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/quitenote-signed-entitlements.XXXXXX")"
codesign --display --entitlements :- "$APP_PATH" > "$SIGNED_ENTITLEMENTS" 2>/dev/null
if plutil -extract 'com.apple.security.files.downloads.read-write' raw -o - "$SIGNED_ENTITLEMENTS" 2>/dev/null | grep -qx 'true'; then
    rm -f "$SIGNED_ENTITLEMENTS"
    echo "❌ 最终应用仍带 Downloads 文件夹读写权限。"
    echo "   请改用用户选择目录和 security-scoped bookmark，不能提交该 entitlement。"
    exit 3
fi
rm -f "$SIGNED_ENTITLEMENTS"

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
