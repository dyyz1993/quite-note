#!/bin/bash
# 文本输入性能测试脚本
# 用于测试不同配置下的文本输入性能

set -e

PROJECT_DIR="/Users/xuyingzhou/Project/study-mac-app/quite-note"
BUILD_LOG="$PROJECT_DIR/performance_test_log.txt"

echo "======================================"
echo "文本输入性能测试"
echo "======================================"
echo ""

# 清理之前的构建
echo "1. 清理之前的构建..."
rm -rf "$PROJECT_DIR/.build"
rm -rf "$PROJECT_DIR/DerivedData"
echo "   ✓ 清理完成"
echo ""

# 构建项目
echo "2. 构建项目..."
cd "$PROJECT_DIR"
./build-app.sh > "$BUILD_LOG" 2>&1
if [ $? -eq 0 ]; then
    echo "   ✓ 构建成功"
else
    echo "   ✗ 构建失败，查看日志: $BUILD_LOG"
    exit 1
fi
echo ""

# 检查是否有性能分析配置
echo "3. 准备性能测试环境..."
if [ ! -f "$PROJECT_DIR/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift" ]; then
    echo "   ✗ 找不到 V2ScreenshotDebugView.swift"
    exit 1
fi
echo "   ✓ 文件检查通过"
echo ""

# 显示测试说明
echo "======================================"
echo "性能测试说明"
echo "======================================"
echo ""
echo "请按照以下步骤进行手动测试："
echo ""
echo "【测试场景 1: 固定高度】"
echo "1. 修改 V2ScreenshotDebugView.swift 第 1398 行："
echo "   将 .frame(width: textEditorWidth, height: textEditorHeight)"
echo "   改为 .frame(width: textEditorWidth, height: 100)"
echo ""
echo "2. 重新构建并运行"
echo ""
echo "3. 在文本编辑器中连续快速输入 50 个字符"
echo ""
echo "4. 观察是否有卡顿，记录主观感受（流畅/轻微卡顿/明显卡顿）"
echo ""
echo "【测试场景 2: 移除 Mask】"
echo "1. 注释掉 V2ScreenshotDebugView.swift 第 1406-1423 行的 .mask {} 部分"
echo ""
echo "2. 重新构建并运行"
echo ""
echo "3. 重复相同的输入测试"
echo ""
echo "4. 记录性能差异"
echo ""
echo "【测试场景 3: 添加 drawingGroup】"
echo "1. 在 .position() 之前添加 .drawingGroup()"
echo ""
echo "2. 重新构建并运行"
echo ""
echo "3. 重复相同的输入测试"
echo ""
echo "4. 记录性能差异"
echo ""
echo "【使用 Instruments 进行精确测量】"
echo "1. 在 Xcode 中打开项目"
echo "2. Product → Profile (或按 Cmd+I)"
echo "3. 选择 'Time Profiler'"
echo "4. 在文本编辑器中输入 50 个字符"
echo "5. 停止记录，查看调用栈"
echo "6. 搜索 'V2ScreenshotDebugView' 或 'TextEditor'"
echo "7. 查看 CPU 时间消耗"
echo ""
echo "【关键性能指标】"
echo "- 每次输入的渲染时间（应该 < 16ms 以保持 60fps）"
echo "- CPU 使用率峰值"
echo "- 内存分配次数"
echo "- 视图更新次数"
echo ""
echo "======================================"
echo ""

# 创建测试结果记录文件
RESULT_FILE="$PROJECT_DIR/performance_test_results.md"
cat > "$RESULT_FILE" << 'EOF'
# 文本输入性能测试结果

## 测试环境
- 日期: [填写测试日期]
- macOS 版本: [填写版本]
- Xcode 版本: [填写版本]
- 设备: [填写设备型号]

## 测试场景 1: 固定高度

### 配置
- TextEditor 高度: 100 (固定)
- Mask: 启用
- drawingGroup: 未启用

### 测试结果
- 输入 50 个字符的耗时: ___ 秒
- 主观感受: [ ] 流畅 [ ] 轻微卡顿 [ ] 明显卡顿
- CPU 使用率峰值: ___ %
- 掉帧次数: ___ 次

### 备注
[填写观察到的任何问题或改进]

---

## 测试场景 2: 移除 Mask

### 配置
- TextEditor 高度: 自适应
- Mask: 禁用
- drawingGroup: 未启用

### 测试结果
- 输入 50 个字符的耗时: ___ 秒
- 主观感受: [ ] 流畅 [ ] 轻微卡顿 [ ] 明显卡顿
- CPU 使用率峰值: ___ %
- 掉帧次数: ___ 次

### 备注
[填写观察到的任何问题或改进]

---

## 测试场景 3: 添加 drawingGroup

### 配置
- TextEditor 高度: 自适应
- Mask: 启用
- drawingGroup: 启用

### 测试结果
- 输入 50 个字符的耗时: ___ 秒
- 主观感受: [ ] 流畅 [ ] 轻微卡顿 [ ] 明显卡顿
- CPU 使用率峰值: ___ %
- 掉帧次数: ___ 次

### 备注
[填写观察到的任何问题或改进]

---

## 对比分析

| 方案 | 耗时 | 主观感受 | CPU 峰值 | 掉帧次数 | 推荐度 |
|------|------|----------|----------|----------|--------|
| 固定高度 | | | | | ⭐⭐⭐⭐⭐ |
| 移除 Mask | | | | | ⭐⭐⭐⭐ |
| 添加 drawingGroup | | | | | ⭐⭐⭐⭐ |

---

## Instruments 分析

### Time Profiler 结果
[截图或描述最耗时的函数调用]

### Core Animation 结果
- FPS: ___
- GPU 使用率: ___ %

### 结论
[基于测试结果的最终结论]

---

EOF

echo "已创建测试结果记录文件: $RESULT_FILE"
echo ""
echo "======================================"
echo "准备就绪！"
echo "======================================"
echo ""
echo "你现在可以："
echo "1. 按照上述说明进行手动测试"
echo "2. 或使用 Xcode Instruments 进行精确测量"
echo "3. 测试结果记录到: $RESULT_FILE"
echo ""
echo "如需直接运行应用进行快速测试："
echo "   open 'DerivedData/QuiteNote/Build/Products/Debug/QuiteNote.app'"
echo ""
