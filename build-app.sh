#!/bin/bash

# Quite Note 应用构建脚本
set -e

echo "开始构建 Quite Note 应用..."

# 配置变量
APP_NAME="Quite Note"
BUNDLE_ID="com.quitenote.app"
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
cp .build/release/$EXECUTABLE_NAME "$MACOS_DIR/"

# 复制图标文件
if [ -f "AppIcon.icns" ]; then
    echo "复制应用图标..."
    cp AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "QuiteNote.icns" ]; then
    echo "复制备用应用图标..."
    cp QuiteNote.icns "$RESOURCES_DIR/AppIcon.icns"
fi

# 转换 SVG 为 PNG 状态栏图标
if [ -f "StatusBarIcon.svg" ]; then
    echo "转换 SVG 为 PNG 状态栏图标..."
    convert StatusBarIcon.svg -resize 36x36 "$RESOURCES_DIR/StatusBarIcon.png"
elif [ -f "AppIcon.svg" ]; then
    echo "转换应用图标 SVG 为 PNG 状态栏图标..."
    convert AppIcon.svg -resize 36x36 "$RESOURCES_DIR/AppIcon.png"
fi

# 复制 LucideIcons 资源包
# 注意：对于 macOS 应用，框架和资源包通常应放置在 Contents/Frameworks 目录下
# 这样才能被应用程序正确加载。
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

if [ -d ".build/arm64-apple-macosx/release/LucideIcons_LucideIcons.bundle" ]; then
    echo "复制 LucideIcons 资源包到 Frameworks 目录..."
    cp -R ".build/arm64-apple-macosx/release/LucideIcons_LucideIcons.bundle" "$FRAMEWORKS_DIR/"
elif [ -d ".build/release/LucideIcons_LucideIcons.bundle" ]; then
    echo "复制 LucideIcons 资源包到 Frameworks 目录 (通用路径)..."
    cp -R ".build/release/LucideIcons_LucideIcons.bundle" "$FRAMEWORKS_DIR/"
else
    echo "警告：未找到 LucideIcons 资源包，请检查构建配置。"
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
</dict>
</plist>
EOF

# 设置权限
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

echo "应用构建完成！"
echo "应用位置: $APP_PATH"
echo ""
echo "要运行应用，请执行:"
echo "open \"$APP_PATH\""
echo ""
echo "要创建 DMG 安装包，请执行:"
echo "./create-dmg.sh"