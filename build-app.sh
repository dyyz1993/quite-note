#!/bin/bash

# Quite Note 应用构建脚本
set -e

echo "开始构建 Quite Note 应用..."

# 配置变量
APP_NAME="Quite Note Dev"
BUNDLE_ID="com.quitenote.app.dev"
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
case "${1:-}" in
    --check-permissions)
        checkPermissions "$BUNDLE_ID"
        exit 0
        ;;
    --help|-h)
        showUsage
        exit 0
        ;;
esac

# 构建 release 版本
echo "正在编译应用..."
swift build -c release --product QuiteNote

# 创建应用包结构
APP_PATH="$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "创建应用包结构..."
rm -rf "$APP_PATH"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 复制二进制文件
echo "复制二进制文件..."
if [ -f ".build/apple/Products/Release/$EXECUTABLE_NAME" ]; then
    cp ".build/apple/Products/Release/$EXECUTABLE_NAME" "$MACOS_DIR/"
elif [ -f ".build/release/$EXECUTABLE_NAME" ]; then
    cp ".build/release/$EXECUTABLE_NAME" "$MACOS_DIR/"
else
    # 尝试在所有可能的路径中查找最新的二进制文件
    FOUND_BIN=$(find .build -name "$EXECUTABLE_NAME" -type f -path "*/release/*" | head -n 1)
    if [ -n "$FOUND_BIN" ]; then
        echo "在 $FOUND_BIN 找到二进制文件"
        cp "$FOUND_BIN" "$MACOS_DIR/"
    else
        echo "错误：找不到编译好的二进制文件 $EXECUTABLE_NAME"
        exit 1
    fi
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
if [ -d ".build/arm64-apple-macosx/release/LucideIcons_LucideIcons.bundle/icons.xcassets" ]; then
    echo "复制 LucideIcons 资源到 Resources 目录..."
    cp -R ".build/arm64-apple-macosx/release/LucideIcons_LucideIcons.bundle/icons.xcassets" "$RESOURCES_DIR/"
elif [ -d ".build/release/LucideIcons_LucideIcons.bundle/icons.xcassets" ]; then
    echo "复制 LucideIcons 资源到 Resources 目录 (通用路径)..."
    cp -R ".build/release/LucideIcons_LucideIcons.bundle/icons.xcassets" "$RESOURCES_DIR/"
else
    echo "警告：未找到 LucideIcons 资源，请检查构建配置。"
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

# 代码签名 (使用临时签名，避免"损坏"问题)
echo "正在对应用进行代码签名..."
if command -v codesign >/dev/null 2>&1; then
    # 签名可执行文件
    codesign --force --sign - "$MACOS_DIR/$EXECUTABLE_NAME"
    
    # 最后签名整个应用包
    codesign --force --sign - "$APP_PATH"
    echo "代码签名完成"
else
    echo "警告：未找到 codesign 工具，跳过代码签名"
fi

# 检查并引导权限设置
guidePermissions "$BUNDLE_ID"

echo "应用构建完成！"
echo "应用位置: $APP_PATH"
echo "open \"$APP_PATH\""

echo ""

# 自动重启应用
echo "正在重启应用..."
# 杀死可能正在运行的旧版本（匹配可执行文件名）
pkill -x "$EXECUTABLE_NAME" || true
# 等待一秒确保进程已释放资源
sleep 1
# 打开新构建的应用
open "$APP_PATH"

echo "应用已重启并启动。"

exit 0
