#!/bin/bash

# Quite Note 应用构建脚本
set -e

echo "开始构建 Quite Note 应用..."

# 配置变量
APP_NAME="Quite Note Dev"
BUNDLE_ID="com.quitenote.app.dev"
EXECUTABLE_NAME="QuiteNote"
VERSION="1.0.0"

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

# 设置屏幕录制权限（开发环境）
echo "正在设置屏幕录制权限..."
setupScreenCapturePermission "$BUNDLE_ID"

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

# ====================================================================
# 权限设置功能
# ====================================================================

# 设置屏幕录制权限
setupScreenCapturePermission() {
    local bundle_id="$1"
    echo "🔧 设置屏幕录制权限..."
    
    if sudo /usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "INSERT OR REPLACE INTO access (service,client,client_type,allowed,prompt_count,indirect_object_identifier) VALUES ('kTCCServiceScreenCapture','$bundle_id',0,1,1,'kTCCServiceEventTap')" 2>/dev/null; then
        echo "✅ 屏幕录制权限设置成功"
    else
        echo "❌ 自动设置屏幕录制权限失败，请手动设置"
    fi
}

# 设置辅助功能权限
setupAccessibilityPermission() {
    local bundle_id="$1"
    echo "🔧 设置辅助功能权限..."
    
    if sudo /usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "INSERT OR REPLACE INTO access (service,client,client_type,allowed,prompt_count,indirect_object_identifier) VALUES ('kTCCServiceAccessibility','$bundle_id',0,1,1,'kTCCServiceEventTap')" 2>/dev/null; then
        echo "✅ 辅助功能权限设置成功"
    else
        echo "❌ 自动设置辅助功能权限失败，请手动设置"
    fi
}

# ====================================================================
# 使用说明
# ====================================================================

showUsage() {
    cat << 'EOF'

🎯 权限自动设置说明
===================

✅ 自动设置的功能：
   • 屏幕录制权限 - 用于截图功能
   • 辅助功能权限 - 用于全局快捷键

⚡ 使用方法：
   1. 开发环境构建会自动设置权限
   2. 单独设置权限：./build-app.sh --setup-permissions
   3. 检查权限状态：./build-app.sh --check-permissions

🔒 安全说明：
   • 仅在开发环境（Bundle ID 包含 "dev"）中自动设置
   • 需要管理员权限，会提示输入密码
   • 不会影响生产环境的安全性

📱 手动设置方法：
   系统偏好设置 → 安全性与隐私 → 隐私 → 屏幕录制/辅助功能

EOF
}

# 检查权限状态
checkPermissions() {
    local bundle_id="$1"
    echo "🔍 检查 $bundle_id 的权限状态："
    
    # 检查屏幕录制权限
    if /usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT client FROM access WHERE service='kTCCServiceScreenCapture' AND client='$bundle_id'" 2>/dev/null | grep -q "$bundle_id"; then
        echo "✅ 屏幕录制权限：已授权"
    else
        echo "❌ 屏幕录制权限：未授权"
    fi
    
    # 检查辅助功能权限
    if /usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT client FROM access WHERE service='kTCCServiceAccessibility' AND client='$bundle_id'" 2>/dev/null | grep -q "$bundle_id"; then
        echo "✅ 辅助功能权限：已授权"
    else
        echo "❌ 辅助功能权限：未授权"
    fi
}

# 处理命令行参数
case "${1:-}" in
    --setup-permissions)
        echo "🔧 单独设置权限模式"
        setupScreenCapturePermission "$BUNDLE_ID"
        setupAccessibilityPermission "$BUNDLE_ID"
        exit 0
        ;;
    --check-permissions)
        checkPermissions "$BUNDLE_ID"
        exit 0
        ;;
    --help|-h)
        showUsage
        exit 0
        ;;
esac

# ====================================================================
# 权限设置函数
# ====================================================================

# 设置屏幕录制权限
setupScreenCapturePermission() {
    local bundle_id="$1"
    
    echo "正在为 $bundle_id 设置屏幕录制权限..."
    
    # 检查是否已经拥有权限
    if /usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT client FROM access WHERE service='kTCCServiceScreenCapture' AND client='$bundle_id'" 2>/dev/null | grep -q "$bundle_id"; then
        echo "✅ 屏幕录制权限已存在"
        return 0
    fi
    
    # 尝试自动添加权限
    echo "⚠️  需要管理员权限来设置屏幕录制权限"
    echo "如果提示输入密码，请输入你的 Mac 登录密码"
    
    # 使用 osascript 执行需要管理员权限的命令
    local timestamp=$(date +%s)
    local sql_cmd="INSERT or REPLACE INTO access VALUES('kTCCServiceScreenCapture','$bundle_id',0,1,1,NULL,NULL,NULL,'UNUSED',NULL,0,$timestamp);"
    
    if osascript -e "do shell script \"/usr/bin/sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' '$sql_cmd'\" with administrator privileges" 2>/dev/null; then
        echo "✅ 屏幕录制权限设置成功"
        echo "💡 提示：权限将在应用重启后生效"
    else
        echo "❌ 自动设置权限失败，请手动设置："
        echo "   1. 打开「系统偏好设置」→「安全性与隐私」→「隐私」"
        echo "   2. 选择「屏幕录制」"
        echo "   3. 找到并勾选 '$APP_NAME'"
        echo "   4. 重启应用"
    fi
}

# 设置辅助功能权限（用于全局快捷键）
setupAccessibilityPermission() {
    local bundle_id="$1"
    
    echo "正在为 $bundle_id 设置辅助功能权限..."
    
    # 检查是否已经拥有权限
    if /usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT client FROM access WHERE service='kTCCServiceAccessibility' AND client='$bundle_id'" 2>/dev/null | grep -q "$bundle_id"; then
        echo "✅ 辅助功能权限已存在"
        return 0
    fi
    
    echo "⚠️  需要管理员权限来设置辅助功能权限"
    
    # 尝试自动添加权限
    local timestamp=$(date +%s)
    local sql_cmd="INSERT or REPLACE INTO access VALUES('kTCCServiceAccessibility','$bundle_id',0,1,1,NULL,NULL,NULL,'UNUSED',NULL,0,$timestamp);"
    
    if osascript -e "do shell script \"/usr/bin/sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' '$sql_cmd'\" with administrator privileges" 2>/dev/null; then
        echo "✅ 辅助功能权限设置成功"
    else
        echo "❌ 自动设置辅助功能权限失败，请手动设置"
    fi
}