#!/bin/bash
# 权限检查和设置辅助脚本

echo "=========================================="
echo "Quite Note 权限检查"
echo "=========================================="
echo ""

# 检查应用是否存在
APP_PATH="Quite Note Dev.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 找不到应用: $APP_PATH"
    echo "请先运行 build-app.sh 构建应用"
    exit 1
fi

BUNDLE_ID="com.quitenote.app.dev"
echo "应用 Bundle ID: $BUNDLE_ID"
echo ""

# 读取当前权限状态
echo "检查权限状态..."
echo ""

# 使用 tccutil 检查
echo "使用 tccutil 检查权限:"
tccutil list 2>/dev/null | grep -i "$BUNDLE_ID" || echo "  找不到权限配置"
echo ""

echo "=========================================="
echo "需要手动授权的权限"
echo "=========================================="
echo ""
echo "1. 屏幕录制权限（必需）"
echo "   - 用于截取屏幕和检测窗口"
echo "   - 设置路径: 系统设置 > 隐私与安全性 > 屏幕录制"
echo ""
echo "2. 辅助功能权限（推荐）"
echo "   - 用于全局快捷键"
echo "   - 设置路径: 系统设置 > 隐私与安全性 > 辅助功能"
echo ""

echo "=========================================="
echo "打开系统设置"
echo "=========================================="
echo ""

# 打开屏幕录制设置
echo "正在打开屏幕录制设置..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

sleep 1

echo ""
echo "✅ 请在打开的窗口中找到 'Quite Note Dev' 并开启开关"
echo ""
echo "开启后，如果功能仍然无效，请尝试："
echo "  1. 关闭开关，等待 2 秒"
echo "  2. 重新开启开关"
echo "  3. 重启应用"
echo ""

