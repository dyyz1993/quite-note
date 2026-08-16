#!/bin/bash

# Quite Note 应用构建脚本
set -e

echo "开始构建 Quite Note 应用..."

# 配置变量
# APP_NAME="Quite Note Dev"
# BUNDLE_ID="com.quitenote.app.dev"
APP_NAME="Quite Note"
BUNDLE_ID="com.quitenote.app"
EXECUTABLE_NAME="QuiteNote"
VERSION="1.0.0"

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

macOS (11.0+) 对「屏幕录制」和「辅助功能」有极严的安全限制。
脚本无法完全自动开启这些权限，必须由用户在系统设置中手动确认。

⚡ 使用方法：
   1. 正常构建：./build-app.sh (会自动运行检查)
   2. 检查权限状态：./build-app.sh --check-permissions
   3. 帮助说明：./build-app.sh --help

� 手动确认路径：
   系统设置 → 隐私与安全性 → 屏幕录制
   系统设置 → 隐私与安全性 → 辅助功能

EOF
}

# 处理命令行参数
SKIP_BUILD=false
case "${1:-}" in
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
        echo "发布模式：构建完成后不重启应用..."
        ;;
esac

# 构建 release 版本
if [ "$SKIP_BUILD" = false ]; then
    echo "正在编译应用..."
    swift build -c release --product QuiteNote
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

if [ -f ".build/apple/Products/Release/$EXECUTABLE_NAME" ]; then
    SOURCE_BIN=".build/apple/Products/Release/$EXECUTABLE_NAME"
elif [ -f ".build/release/$EXECUTABLE_NAME" ]; then
    SOURCE_BIN=".build/release/$EXECUTABLE_NAME"
else
    # 尝试在所有可能的路径中查找最新的二进制文件
    SOURCE_BIN=$(find .build -name "$EXECUTABLE_NAME" -type f -path "*/release/*" | head -n 1)
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
        cp "$SOURCE_BIN" "$MACOS_DIR/"
        BINARY_CHANGED=true
    else
        echo "二进制文件未变化（MD5: $SOURCE_HASH），跳过复制"
    fi
else
    echo "首次复制二进制文件"
    cp "$SOURCE_BIN" "$MACOS_DIR/"
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
LUCIDE_BUNDLE_PATH=$(find .build -name "LucideIcons_LucideIcons.bundle" -type d -path "*/release/*" | head -n 1)

if [ -n "$LUCIDE_BUNDLE_PATH" ] && [ -d "$LUCIDE_BUNDLE_PATH/icons.xcassets" ]; then
    echo "在 $LUCIDE_BUNDLE_PATH 找到 LucideIcons 资源，复制到 Resources 目录..."
    # 先删除旧的，避免权限问题
    rm -rf "$RESOURCES_DIR/icons.xcassets"
    cp -R "$LUCIDE_BUNDLE_PATH/icons.xcassets" "$RESOURCES_DIR/"
else
    echo "警告：未找到 LucideIcons 资源，请检查构建配置。"
fi

# 复制 QuiteNote 资源文件（包括 YAML 配置文件）
QUITENOTE_BUNDLE_PATH=$(find .build -name "QuiteNote_QuiteNote.bundle" -type d -path "*/release/*" | head -n 1)

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
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Quite Note 需要访问蓝牙来发现和连接附近的设备，用于设备间数据同步和分享功能。</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Quite Note 使用蓝牙来与周边设备通信，实现剪切板内容的快速分享和同步。</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>Quite Note 需要系统管理权限来监听全局键盘快捷键，实现快速调用剪切板历史功能。</string>
    <key>NSScreenCaptureDescription</key>
    <string>Quite Note 需要屏幕录制权限来执行截图功能，帮助您快速截取和保存屏幕内容。</string>
</dict>
</plist>
EOF

# 设置权限
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

# 代码签名 (只在二进制变化时重新签名)
if [ "$BINARY_CHANGED" = true ]; then
    echo "二进制文件已变化，正在重新签名..."

    if command -v codesign >/dev/null 2>&1; then
        # 优先用 Apple Development 证书签名：签名身份锚定在 Team ID + Bundle ID 上，
        # 重新编译后系统权限（屏幕录制/辅助功能）不会失效。
        # ad-hoc 签名身份每次编译都变，会导致权限被系统重置、每次都要重新授权。
        DEV_IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
        if [ -n "$DEV_IDENTITY" ]; then
            codesign --force --deep --sign "$DEV_IDENTITY" "$APP_PATH" --identifier "$BUNDLE_ID"
            echo "代码签名完成 (Apple Development 证书，权限可跨编译保留)"
        else
            codesign --force --deep --sign - "$APP_PATH" --identifier "$BUNDLE_ID"
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
