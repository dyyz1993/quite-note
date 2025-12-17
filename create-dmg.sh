#!/bin/bash

# 创建 DMG 安装包脚本
set -e

APP_NAME="Quite Note"
DMG_NAME="QuiteNote"
VERSION="1.0.0"

echo "创建 DMG 安装包..."

# 检查应用是否存在
if [ ! -d "$APP_NAME.app" ]; then
    echo "错误: 找不到 $APP_NAME.app，请先运行 build-app.sh"
    exit 1
fi

# 创建临时 DMG 目录
DMG_DIR="dmg_temp"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# 复制应用到 DMG 目录
cp -R "$APP_NAME.app" "$DMG_DIR/"

# 创建应用程序文件夹链接
ln -s /Applications "$DMG_DIR/Applications"

# 创建 DMG
DMG_FILE="$DMG_NAME-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO -imagekey zlib-level=9 "$DMG_FILE"

# 清理临时目录
rm -rf "$DMG_DIR"

echo "DMG 创建完成: $DMG_FILE"