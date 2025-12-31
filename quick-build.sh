#!/bin/bash

# 快速开发构建 - 只编译不重启
# 用于快速迭代开发

echo "⚡ 快速构建中..."

# 编译
swift build -c release --product QuiteNote 2>&1 | grep -E "(error:|warning:|Build complete)" || true

# 只更新二进制，不重启应用
APP_NAME="Quite Note Dev"
EXECUTABLE_NAME="QuiteNote"
MACOS_DIR="$APP_NAME.app/Contents/MacOS"

# 找到最新的二进制
SOURCE_BIN=$(find .build -name "$EXECUTABLE_NAME" -type f -path "*/release/*" | head -n 1)

if [ -n "$SOURCE_BIN" ]; then
    # 检查是否有变化
    if [ -f "$MACOS_DIR/$EXECUTABLE_NAME" ]; then
        SOURCE_HASH=$(md5 -q "$SOURCE_BIN")
        TARGET_HASH=$(md5 -q "$MACOS_DIR/$EXECUTABLE_NAME")

        if [ "$SOURCE_HASH" != "$TARGET_HASH" ]; then
            echo "📦 更新二进制..."
            cp "$SOURCE_BIN" "$MACOS_DIR/"
            chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
            codesign --deep --force --sign - "$APP_NAME.app" 2>&1 | grep -v "replacing existing signature" || true
            echo "✅ 构建完成！(应用未重启)"
        else
            echo "✅ 无变化，跳过构建"
        fi
    else
        echo "❌ 请先运行 ./build-app.sh 创建应用包"
    fi
else
    echo "❌ 编译失败"
fi
