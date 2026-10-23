#!/bin/bash

# Quite Note 应用构建脚本
set -e

echo "开始构建 Quite Note 应用..."

# 配置变量（默认正式变体；加 --dev 参数切换为开发变体，可与正式版共存互不干扰）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Quite Note"
BUNDLE_ID="com.quitenote.app"
EXECUTABLE_NAME="QuiteNote"
BINARY_NAME="QuiteNote"        # swift build 的产物名（两个变体共用同一个二进制）
# 版本号单一真值源 = git 最新 tag（v1.4.0 → 1.4.0），取不到时回退 0.0.0-dev；
# CI 发布仍以 build-release.sh <版本号> 参数为准（会覆写此值）
VERSION="$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
VERSION="${VERSION:-0.0.0-dev}"

# ====================================================================
# 权限检查与引导功能
# ====================================================================

# 检查权限状态
checkPermissions() {
    local bundle_id="$1"
    echo "🔍 正在检查 $bundle_id 的权限状态..."
    
    local has_screen=false
    local has_accessibility=false

    # 检查屏幕录制权限
    if /usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT client FROM access WHERE service='kTCCServiceScreenCapture' AND client='$bundle_id' AND allowed=1" 2>/dev/null | grep -q "$bundle_id"; then
        echo "✅ 屏幕录制权限：已授权"
        has_screen=true
    else
        echo "❌ 屏幕录制权限：未授权或需要手动确认"
    fi
    
    # 检查辅助功能权限
    if /usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT client FROM access WHERE service='kTCCServiceAccessibility' AND client='$bundle_id' AND allowed=1" 2>/dev/null | grep -q "$bundle_id"; then
        echo "✅ 辅助功能权限：已授权"
        has_accessibility=true
    else
        echo "❌ 辅助功能权限：未授权"
    fi

    if [ "$has_screen" = false ] || [ "$has_accessibility" = false ]; then
        echo ""
        echo "💡 提示：由于 macOS 安全机制，即使通过脚本申请权限，通常仍需手动开启："
        echo "   1. 运行应用后，如果弹出权限请求，请点击「打开系统设置」"
        echo "   2. 在「隐私与安全性」中找到「屏幕录制」和「辅助功能」"
        echo "   3. 确保 '$APP_NAME' 的开关已开启"
        echo "   4. 如果开关已开启但功能无效，请尝试「关闭再重新开启」"
    fi
}

# 引导设置权限
guidePermissions() {
    local bundle_id="$1"
    echo "正在检查应用权限..."
    checkPermissions "$bundle_id"
}

showUsage() {
    cat << 'EOF'

🎯 权限设置说明
===================

macOS (13.0+) 对「屏幕录制」和「辅助功能」有极严的安全限制。
脚本无法完全自动开启这些权限，必须由用户在系统设置中手动确认。

⚡ 使用方法：
   1. 正常构建：./build-app.sh (会自动运行检查)
   2. 开发变体：./build-app.sh --dev (构建 Quite Note Dev，可与正式版共存)
   3. App Store 沙盒本地验证：./build-app.sh --app-store --no-launch
   4. 检查权限状态：./build-app.sh --check-permissions
   5. 帮助说明：./build-app.sh --help

� 手动确认路径：
   系统设置 → 隐私与安全性 → 屏幕录制
   系统设置 → 隐私与安全性 → 辅助功能

EOF
}

# 处理命令行参数（支持组合，如 ./build-app.sh --dev --no-launch）
SKIP_BUILD=false
APP_STORE_MODE=false
ENTITLEMENTS_FILE="$SCRIPT_DIR/QuiteNote.entitlements"
for arg in "$@"; do
    case "$arg" in
        --check-permissions)
            checkPermissions "$BUNDLE_ID"
            exit 0
            ;;
        --help|-h)
            showUsage
            exit 0
            ;;
        --no-build)
            SKIP_BUILD=true
            echo "跳过编译，只更新应用包..."
            ;;
        --no-launch)
            NO_LAUNCH=true
            echo "构建完成后不重启应用..."
            ;;
        --dev)
            APP_NAME="Quite Note Dev"
            BUNDLE_ID="com.quitenote.app.dev"
            EXECUTABLE_NAME="QuiteNoteDev"
            echo "开发变体: $APP_NAME ($BUNDLE_ID)"
            ;;
        --install)
            INSTALL_TO_APPLICATIONS=true
            echo "构建后同步到 /Applications 并从那里启动（登录项指向处）..."
            ;;
        --app-store)
            APP_STORE_MODE=true
            ENTITLEMENTS_FILE="$SCRIPT_DIR/QuiteNote-AppStore.entitlements"
            echo "App Store 沙盒验证模式（本地签名，不代表可直接上传）"
            ;;
    esac
done

# 构建 release 版本
if [ "$SKIP_BUILD" = false ]; then
    echo "正在编译应用..."
    # App Store target must compile out integrations that macOS App Sandbox
    # cannot support (for example arbitrary process control and home-folder
    # file crawling). The Developer ID/open-source build keeps those optional
    # power-user integrations.
    SWIFT_BUILD_ARGS=(-c release --product QuiteNote)
    if [ "$APP_STORE_MODE" = true ]; then
        SWIFT_BUILD_ARGS+=(-Xswiftc -D -Xswiftc APP_STORE)
    fi
    # GitHub's macos-15 runners expose the older SDK used by Tests; keep the
    # production speech UI compilable there while local macOS 26 builds retain it.
    SWIFT_BUILD_ARGS+=(
        -Xswiftc -D -Xswiftc LEGACY_CI_SDK
        -Xswiftc -Xfrontend -Xswiftc -solver-expression-time-threshold=1000
    )
    # Sparkle.framework 打进 Contents/Frameworks，主二进制以 @rpath 引用——
    # 必须注入这条 rpath，否则 dyld 加载即失败（"Library not loaded: @rpath/Sparkle.framework"）
    if [ "$APP_STORE_MODE" = false ]; then
        SWIFT_BUILD_ARGS+=(-Xlinker -rpath -Xlinker "@executable_path/../Frameworks")
    fi
    if [ "$BUNDLE_ID" = "com.quitenote.app.dev" ]; then
        echo "开发变体将同时构建常驻核心..."
        swift build -c release --product QuiteNoteCoreService
    fi
    swift build "${SWIFT_BUILD_ARGS[@]}"
else
    echo "使用已编译的二进制文件..."
fi

# 创建应用包结构
APP_PATH="$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "创建应用包结构..."

# 确保目录存在
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# ⚠️ 关键修复：如果应用已存在，只更新二进制文件，不删除整个包
# 这样可以保留 macOS 的权限设置
if [ -d "$APP_PATH" ]; then
    echo "应用包已存在，更新内容（保留权限）..."
    # 只删除二进制文件，确保重新复制
    rm -f "$MACOS_DIR/$EXECUTABLE_NAME"
fi

# 复制二进制文件
echo "复制二进制文件..."
BINARY_CHANGED=false

if [ -f ".build/apple/Products/Release/$BINARY_NAME" ]; then
    SOURCE_BIN=".build/apple/Products/Release/$BINARY_NAME"
elif [ -f ".build/release/$BINARY_NAME" ]; then
    SOURCE_BIN=".build/release/$BINARY_NAME"
else
    # 尝试在所有可能的路径中查找最新的二进制文件
    SOURCE_BIN=$(find .build -name "$BINARY_NAME" -type f -path "*/release/*" | head -n 1)
    if [ -z "$SOURCE_BIN" ]; then
        echo "错误：找不到编译好的二进制文件 $EXECUTABLE_NAME"
        exit 1
    fi
    echo "在 $SOURCE_BIN 找到二进制文件"
fi

# 检查二进制文件是否变化（使用 MD5 比较内容）
if [ -f "$MACOS_DIR/$EXECUTABLE_NAME" ]; then
    SOURCE_HASH=$(md5 -q "$SOURCE_BIN")
    TARGET_HASH=$(md5 -q "$MACOS_DIR/$EXECUTABLE_NAME")

    if [ "$SOURCE_HASH" != "$TARGET_HASH" ]; then
        echo "二进制文件已变化（MD5: $SOURCE_HASH），需要更新"
        cp "$SOURCE_BIN" "$MACOS_DIR/$EXECUTABLE_NAME"
        BINARY_CHANGED=true
    else
        echo "二进制文件未变化（MD5: $SOURCE_HASH），跳过复制"
    fi
else
    echo "首次复制二进制文件"
    cp "$SOURCE_BIN" "$MACOS_DIR/$EXECUTABLE_NAME"
    BINARY_CHANGED=true
fi

# 复制图标文件
if [ -f "AppIcon.icns" ]; then
    echo "复制应用图标..."
    cp AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "QuiteNote.icns" ]; then
    echo "复制备用应用图标..."
    cp QuiteNote.icns "$RESOURCES_DIR/AppIcon.icns"
fi

# 转换 SVG 为 PNG 状态栏图标
if [ -f "generate_icon.swift" ]; then
    echo "使用 Swift 脚本生成状态栏图标..."
    swift generate_icon.swift
    cp StatusBarIcon.png "$RESOURCES_DIR/StatusBarIcon.png"
    # 同时提供 @2x 版本以确保 Retina 屏幕清晰
    cp StatusBarIcon.png "$RESOURCES_DIR/StatusBarIcon@2x.png"
elif [ -f "StatusBarIcon.svg" ]; then
    echo "转换 SVG 为 PNG 状态栏图标..."
    # 使用 -background none 确保背景透明，这对菜单栏图标至关重要
    magick -background none StatusBarIcon.svg -resize 36x36 "$RESOURCES_DIR/StatusBarIcon.png" || convert -background none StatusBarIcon.svg -resize 36x36 "$RESOURCES_DIR/StatusBarIcon.png"
elif [ -f "AppIcon.svg" ]; then
    echo "转换应用图标 SVG 为 PNG 状态栏图标..."
    magick -background none AppIcon.svg -resize 36x36 "$RESOURCES_DIR/AppIcon.png" || convert -background none AppIcon.svg -resize 36x36 "$RESOURCES_DIR/AppIcon.png"
fi

# 复制 LucideIcons 资源
# 直接复制资源文件到 Resources 目录，避免 bundle 签名问题
# 注意：-path 匹配必须兼容 "[Rr]elease"——Xcode 布局的产物在 .build/out/Products/Release/（大写 R），
# 且 .build/release 只是符号链接（find 默认不跟随，靠 -path 永远匹配不到）。
LUCIDE_BUNDLE_PATH=$(find .build -name "LucideIcons_LucideIcons.bundle" -type d -path "*/[Rr]elease/*" | head -n 1)
if [ -z "$LUCIDE_BUNDLE_PATH" ]; then
    LUCIDE_BUNDLE_PATH=$(find .build -name "LucideIcons_LucideIcons.bundle" -type d | head -n 1)
fi

if [ -n "$LUCIDE_BUNDLE_PATH" ] && [ -d "$LUCIDE_BUNDLE_PATH/icons.xcassets" ]; then
    # 旧 SwiftPM 布局：bundle 内是扁平 icons.xcassets，拷进 Resources（正式版既有运行时路径）
    echo "在 $LUCIDE_BUNDLE_PATH 找到 LucideIcons 资源，复制到 Resources 目录..."
    # 先删除旧的，避免权限问题
    rm -rf "$RESOURCES_DIR/icons.xcassets"
    cp -R "$LUCIDE_BUNDLE_PATH/icons.xcassets" "$RESOURCES_DIR/"
elif [ -n "$LUCIDE_BUNDLE_PATH" ]; then
    # 新 swiftbuild 布局：bundle 是 Contents/Resources/Assets.car 编译形态，
    # 整个 bundle 拷进 Frameworks（Icon.swift loadFromKnownBundle 的既有支持路径）
    echo "在 $LUCIDE_BUNDLE_PATH 找到 LucideIcons 资源（编译形态），复制到 Frameworks 目录..."
    mkdir -p "$CONTENTS/Frameworks"
    rm -rf "$CONTENTS/Frameworks/LucideIcons_LucideIcons.bundle"
    cp -R "$LUCIDE_BUNDLE_PATH" "$CONTENTS/Frameworks/"
else
    echo "错误：未找到 LucideIcons 资源，图标将全部空白。终止构建。"
    exit 1
fi

# 复制 Sparkle.framework（在线更新；App Store 沙盒版不用 Sparkle，跳过）
# 来源 = SwiftPM artifact（.build/artifacts/sparkle/.../Sparkle.xcframework，universal）。
# 主二进制以 @rpath/Sparkle.framework 引用，rpath 由构建参数 -Xlinker 注入
# （@executable_path/../Frameworks），见 SWIFT_BUILD_ARGS。
if [ "$APP_STORE_MODE" = false ]; then
    SPARKLE_FRAMEWORK=$(find .build/artifacts -path "*macos-arm64_x86_64/Sparkle.framework" -maxdepth 5 -type d 2>/dev/null | head -n 1)
    if [ -z "$SPARKLE_FRAMEWORK" ]; then
        SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d -path "*macos*" 2>/dev/null | grep -v dSYM | head -n 1)
    fi
    if [ -n "$SPARKLE_FRAMEWORK" ]; then
        echo "在 $SPARKLE_FRAMEWORK 找到 Sparkle.framework，复制到 Frameworks 目录..."
        # CI 的老 SwiftPM 可能把 framework 内容直接铺进 .build 产物 app 的 Frameworks/
        # （无 Sparkle.framework 目录层，导致 codesign 报 "Contents/Frameworks/Versions/B/..."）
        # 检测到该形态时清空重拷
        if [ -e "$CONTENTS/Frameworks/Versions" ]; then
            echo "检测到铺开的 Sparkle 结构（Frameworks/Versions），清理..."
            rm -rf "$CONTENTS/Frameworks"
        fi
        rm -rf "$CONTENTS/Frameworks/Sparkle.framework"
        cp -R "$SPARKLE_FRAMEWORK" "$CONTENTS/Frameworks/"
        echo "[diag2] cp 后 Frameworks 顶层:"
        ls "$CONTENTS/Frameworks/" | head -12
        echo "[diag2] cp 后 Sparkle.framework 是否为目录:"
        [ -d "$CONTENTS/Frameworks/Sparkle.framework" ] && echo "是目录" || echo "不是目录！"
        # 移除 dSYM 目录，减小包体并避免签名噪音
        rm -rf "$CONTENTS/Frameworks/Sparkle.framework/Versions/B/Resources/dSYMs" 2>/dev/null || true
        # 移除非英语本地化：CI 的 codesign 会把 Versions/B/Resources/*.lproj 误判为
        # 子组件导致整包签名失败（"bundle format unrecognized"），运行时回退 en 无损
        find "$CONTENTS/Frameworks/Sparkle.framework/Versions/B/Resources" -name "*.lproj" -not -name "en.lproj" -exec rm -rf {} + 2>/dev/null || true
        # 先独立签名 framework（含嵌套 Updater.app），主包 --deep 签名时不再重签
        if command -v codesign >/dev/null 2>&1 && [ -n "${APP_SIGN_IDENTITY:-}" ]; then
            codesign --force --deep --sign "$APP_SIGN_IDENTITY" "$CONTENTS/Frameworks/Sparkle.framework" 2>/dev/null \
              || codesign --force --deep -s - "$CONTENTS/Frameworks/Sparkle.framework" 2>/dev/null || true
        fi
    else
        echo "警告：未找到 Sparkle.framework，在线更新功能将不可用（构建继续）"
    fi
fi

# 复制 QuiteNote 资源文件（包括 YAML 配置文件）
QUITENOTE_BUNDLE_PATH=$(find .build -name "QuiteNote_QuiteNote.bundle" -type d -path "*/[Rr]elease/*" | head -n 1)
if [ -z "$QUITENOTE_BUNDLE_PATH" ]; then
    QUITENOTE_BUNDLE_PATH=$(find .build -name "QuiteNote_QuiteNote.bundle" -type d | head -n 1)
fi

if [ -n "$QUITENOTE_BUNDLE_PATH" ]; then
    echo "在 $QUITENOTE_BUNDLE_PATH 找到 QuiteNote 资源，复制到 Resources 目录..."
    # 复制 Resources/Symbols 目录下的所有 YAML 文件
    if [ -d "Resources/Symbols" ]; then
        mkdir -p "$RESOURCES_DIR/Symbols"
        cp -R Resources/Symbols/*.yaml "$RESOURCES_DIR/Symbols/" 2>/dev/null || true
        echo "已复制 Symbols YAML 文件到 Resources/Symbols/"
    else
        # 如果没有 Resources/Symbols，尝试从 bundle 复制 default.yaml
        mkdir -p "$RESOURCES_DIR/Symbols"
        if [ -f "$QUITENOTE_BUNDLE_PATH/default.yaml" ]; then
            cp "$QUITENOTE_BUNDLE_PATH/default.yaml" "$RESOURCES_DIR/Symbols/"
            echo "已复制 default.yaml 到 Resources/Symbols/"
        else
            echo "警告：未找到 Symbols 配置文件"
        fi
    fi
else
    echo "警告：未找到 QuiteNote 资源 bundle"
fi

# 复制 Editor 资源文件（包括 yaml-editor.html）
if [ -d "Resources/Editor" ]; then
    echo "复制 Editor 资源到 Resources 目录..."
    mkdir -p "$RESOURCES_DIR/Editor"
    cp -R Resources/Editor/* "$RESOURCES_DIR/Editor/"
    echo "已复制 Editor 资源到 Resources/Editor/"
else
    echo "警告：未找到 Editor 资源目录"
fi

# Copy app-localized UI and privacy-permission copy directly into the staged
# application bundle. The release assembler does not embed SwiftPM's resource
# bundle, so these .lproj directories must live beside Info.plist.
LOCALIZATION_SOURCE="Sources/QuiteNote/Resources/Localization"
if [ -d "$LOCALIZATION_SOURCE" ]; then
    echo "复制本地化资源到 Resources 目录..."
    find "$LOCALIZATION_SOURCE" -type d -name '*.lproj' -print0 | while IFS= read -r -d '' localization_dir; do
        cp -R "$localization_dir" "$RESOURCES_DIR/"
    done
else
    echo "警告：未找到本地化资源目录"
fi

# 创建 Info.plist
echo "创建 Info.plist..."
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>SUPublicEDKey</key>
    <string>lSd4xWWLtuykwCbPH/kYqFZqog7LgcJbJTyPJUyggb0=</string>
    <key>SUFeedURL</key>
    <string>https://dyyz1993.github.io/quite-note/appcast.xml</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Quite Note 需要屏幕录制权限来执行截图功能，帮助您快速截取和保存屏幕内容。</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Quite Note 需要系统声音录制权限来录制您选择的屏幕内容中的音频。</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Quite Note 需要访问麦克风来录制您的解说（口播）。仅在选择「录制麦克风」时使用，可在录屏设置中随时关闭。</string>
</dict>
</plist>
EOF

# 设置权限
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

# 代码签名 (只在二进制变化时重新签名)
if [ "$BINARY_CHANGED" = true ]; then
    echo "[diag] Contents/Frameworks 内容:"
    ls -la "$CONTENTS/Frameworks/" 2>/dev/null || true
    echo "[diag] Sparkle.framework 顶层:"
    ls "$CONTENTS/Frameworks/Sparkle.framework/" 2>/dev/null || true
    echo "二进制文件已变化，正在重新签名..."

    if command -v codesign >/dev/null 2>&1; then
        # 优先用 Developer ID Application 证书签名（与发布流水线同一身份）：
        # 签名身份统一后，开发构建 ↔ 发布构建来回切换不会导致系统权限失效。
        # ad-hoc 签名身份每次编译都变，会导致权限被系统重置、每次都要重新授权。
        if [ -n "${APP_SIGN_IDENTITY:-}" ]; then
            # A keychain may contain duplicate certificates with the same
            # display name. Accept a SHA-1 fingerprint from the caller so
            # codesign receives an unambiguous identity.
            SIGN_IDENTITY="$APP_SIGN_IDENTITY"
        elif [ "$APP_STORE_MODE" = true ]; then
            SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Apple Distribution/{print $1; exit}' | awk '{ print $2 }')
        else
            SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $1; exit}' | awk '{ print $2 }')
        fi
        if [ -z "$SIGN_IDENTITY" ] && [ "$APP_STORE_MODE" = false ]; then
            SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $1; exit}' | awk '{ print $2 }')
        fi
        if [ -n "$SIGN_IDENTITY" ]; then
            # 嵌套 bundle 必须从内到外签：Sparkle.framework（含 Updater.app/XPCServices
            # 子组件）→ 主 app。--deep 已被 CI 的老版 codesign 判死
            # （"bundle format unrecognized ... In subcomponent: .../he.lproj"，
            # 详见 .learnings/ERRORS.md 2026-10-23 条）；显式逐层在两端都稳定。
            SPARKLE_FW="$CONTENTS/Frameworks/Sparkle.framework"
            if [ -d "$SPARKLE_FW" ]; then
                # 先独立签 framework（带 runtime+timestamp，发布可公证）；
                # 预签后主包 --deep 扫描到已有签名即跳过重签，绕开 CI 老 codesign
                # 对嵌套 lproj 的 "bundle format unrecognized" 误判（本机验证一致）
                codesign --force --deep --sign "$SIGN_IDENTITY" "$SPARKLE_FW" --options runtime --timestamp 2>/dev/null \
                  || codesign --force --deep -s - "$SPARKLE_FW" 2>/dev/null || true
            fi
            codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH" --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS_FILE"
            echo "代码签名完成 ($SIGN_IDENTITY，权限可跨编译保留，含音频输入例外)"
        else
            SPARKLE_FW="$CONTENTS/Frameworks/Sparkle.framework"
            if [ -d "$SPARKLE_FW" ]; then
                codesign --force -s - "$SPARKLE_FW" 2>/dev/null || true
            fi
            codesign --force --sign - "$APP_PATH" --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS_FILE"
            echo "代码签名完成 (ad-hoc，注意: 每次编译后系统权限会失效)"
        fi
    else
        echo "警告：未找到 codesign 工具，跳过代码签名"
    fi
else
    echo "二进制文件未变化，跳过签名（保留权限）"
fi

# 检查并引导权限设置
guidePermissions "$BUNDLE_ID"

echo "应用构建完成！"
echo "应用位置: $APP_PATH"
echo "open \"$APP_PATH\""

echo ""

# --install：同步到 /Applications（登录项指向处，日常用这份，避免重启后版本错位）
# 原地更新内容而非删目录重建——保住 macOS TCC 权限（屏幕录制/辅助功能）
if [ "${INSTALL_TO_APPLICATIONS:-false}" = true ] && [ "$APP_STORE_MODE" = false ] && [ "$BUNDLE_ID" = "com.quitenote.app" ]; then
    TARGET_APP="/Applications/$APP_NAME.app"
    echo ""
    echo "正在同步到 $TARGET_APP ..."
    # 优雅退出正在运行的实例（pkill 会触发「异常退出」误报日志）
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
    sleep 2
    # 已有目录则原地更新内容（不 rm 整个包，TCC 权限跟着目录走）
    mkdir -p "$TARGET_APP"
    ditto "$APP_PATH" "$TARGET_APP"
    open "$TARGET_APP"
    echo "已同步到 /Applications 并启动（开机登录项即此路径）。"
    exit 0
fi

# 自动重启应用（发布模式 --no-launch 下跳过）
if [ "${NO_LAUNCH:-false}" = false ]; then
    echo "正在重启应用..."
    # 杀死可能正在运行的旧版本（匹配可执行文件名）
    pkill -x "$EXECUTABLE_NAME" || true
    # 等待一秒确保进程已释放资源
    sleep 1
    # 打开新构建的应用
    open "$APP_PATH"

    echo "应用已重启并启动。"
else
    echo "已跳过应用重启（--no-launch）。"
fi

exit 0
