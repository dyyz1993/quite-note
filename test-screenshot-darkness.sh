#!/bin/bash
# 截图蒙层问题自动化测试脚本

set -e

echo "=========================================="
echo "Quite Note 截图蒙层问题测试"
echo "=========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查应用是否存在
APP_PATH="Quite Note Dev.app"
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ 找不到应用: $APP_PATH${NC}"
    echo "正在构建应用..."
    ./build-app.sh

    if [ ! -d "$APP_PATH" ]; then
        echo -e "${RED}❌ 构建失败${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ 应用已准备好${NC}"
echo ""

# 检查权限状态
echo "=========================================="
echo "检查权限状态"
echo "=========================================="
echo ""

BUNDLE_ID="com.quitenote.app.dev"
PERMISSION_CHECK=$(tccutil list 2>/dev/null | grep -i "$BUNDLE_ID" || echo "")

if [ -z "$PERMISSION_CHECK" ]; then
    echo -e "${YELLOW}⚠️  未找到权限配置${NC}"
    echo "正在打开系统设置..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    echo ""
    echo "请手动授权 'Quite Note Dev' 的屏幕录制权限"
    echo "授权后按回车继续..."
    read
else
    echo -e "${GREEN}✅ 找到权限配置:${NC}"
    echo "$PERMISSION_CHECK"
fi

echo ""

# 关闭已运行的实例
echo "=========================================="
echo "关闭已运行的实例"
echo "=========================================="
echo ""

if pgrep -f "Quite Note Dev" > /dev/null; then
    echo "正在关闭应用..."
    killall Quite\ Note\ Dev 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}✅ 应用已关闭${NC}"
else
    echo "应用未运行"
fi

echo ""

# 启动应用
echo "=========================================="
echo "启动应用"
echo "=========================================="
echo ""

echo "正在启动应用..."
open -a "Quite Note Dev"

sleep 2

if pgrep -f "Quite Note Dev" > /dev/null; then
    echo -e "${GREEN}✅ 应用已启动${NC}"
else
    echo -e "${RED}❌ 应用启动失败${NC}"
    exit 1
fi

echo ""

# 测试说明
echo "=========================================="
echo "测试步骤"
echo "=========================================="
echo ""

echo -e "${YELLOW}步骤 1: 触发简单蒙层测试${NC}"
echo "  1. 按 ⌘⇧S (Cmd+Shift+S) 触发截图"
echo "  2. 应该先看到简单蒙层测试（黑色半透明蒙层）"
echo "  3. 蒙层会显示 5 秒后自动关闭"
echo ""

echo -e "${YELLOW}步骤 2: 触发窗口识别截图${NC}"
echo "  1. 简单蒙层关闭后，会自动显示窗口选择界面"
echo "  2. 检查是否能看到蒙层（屏幕变暗）"
echo "  3. 移动鼠标到窗口上，应该看到蓝色高亮框"
echo ""

echo -e "${YELLOW}步骤 3: 查看日志${NC}"
echo "  1. 打开 Console.app (应用程序 > 实用工具 > 控制台)"
echo "  2. 在搜索框输入 'Quite Note'"
echo "  3. 查找以下关键日志："
echo "     - [SimpleMaskTest] ✅ 蒙层已显示"
echo "     - [V2WindowHighlightView] 过滤后窗口数: X"
echo ""

echo -e "${GREEN}准备就绪！请按照上述步骤测试${NC}"
echo ""

# 提示如何查看日志
echo "=========================================="
echo "查看实时日志"
echo "=========================================="
echo ""

echo "运行以下命令查看实时日志："
echo ""
echo "  log stream --predicate 'process == \"Quite Note Dev\"' --level debug"
echo ""

# 询问是否打开日志
read -p "是否打开日志查看器？(y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log stream --predicate 'process == "Quite Note Dev"' --level debug &
    LOG_PID=$!

    echo -e "${GREEN}✅ 日志查看器已启动 (PID: $LOG_PID)${NC}"
    echo "按 Ctrl+C 停止日志查看"
    echo ""
    echo "现在可以按 ⌘⇧S 开始测试"
    echo ""

    # 等待用户中断
    wait $LOG_PID
else
    echo "现在可以按 ⌘⇧S 开始测试"
fi

echo ""
echo "=========================================="
echo "测试完成"
echo "=========================================="
echo ""

echo -e "${YELLOW}如果蒙层显示正常，问题已解决 ✅${NC}"
echo -e "${RED}如果蒙层仍然不显示，请查看 SCREENSHOT_FIX_GUIDE.md${NC}"
echo ""

echo "测试结果反馈："
echo "1. 简单蒙层测试是否显示？ (是/否)"
echo "2. 窗口识别蒙层是否显示？ (是/否)"
echo "3. Console.app 中的日志输出是什么？"
echo ""
