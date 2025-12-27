#!/bin/bash

# Quite Note 运行脚本
# 直接运行编译后的二进制文件，权限永久保留

set -e

APP_NAME="Quite Note Dev"
EXECUTABLE_NAME="QuiteNote"

echo "🚀 启动 $APP_NAME..."

# 查找编译后的二进制文件
EXEC_PATH=""
if [ -f ".build/apple/Products/Release/$EXECUTABLE_NAME" ]; then
    EXEC_PATH=".build/apple/Products/Release/$EXECUTABLE_NAME"
elif [ -f ".build/release/$EXECUTABLE_NAME" ]; then
    EXEC_PATH=".build/release/$EXECUTABLE_NAME"
else
    # 尝试在所有可能的路径中查找
    EXEC_PATH=$(find .build -name "$EXECUTABLE_NAME" -type f -path "*/release/*" | head -n 1)
fi

if [ -z "$EXEC_PATH" ]; then
    echo "❌ 错误：找不到编译后的二进制文件"
    echo "💡 请先运行: swift build -c release"
    exit 1
fi

if [ ! -f "$EXEC_PATH" ]; then
    echo "❌ 错误：二进制文件不存在: $EXEC_PATH"
    exit 1
fi

echo "📂 二进制文件: $EXEC_PATH"
echo ""
echo "💡 提示："
echo "   - 首次运行请在系统设置中授权屏幕录制和辅助功能权限"
echo "   - 权限授权后会永久保留，无需重复授权"
echo "   - 如需重新编译，运行: swift build -c release"
echo ""

# 杀死可能正在运行的旧版本
pkill -x "$EXECUTABLE_NAME" 2>/dev/null || true
sleep 1

# 直接运行二进制文件
echo "启动应用..."
exec "$EXEC_PATH"
