#!/bin/bash

# 截图功能性能和稳定性测试脚本
# 此脚本将自动触发截图并记录性能数据

LOG_FILE="/tmp/screenshot_performance_test.log"
DEBUG_LOG="/tmp/v2_window_debug.log"
TIMING_LOG="/tmp/screenshot_timing.log"
APP_NAME="Quite Note Dev"

# 清空日志
> "$LOG_FILE"
> "$TIMING_LOG"
> "$DEBUG_LOG"

echo "========================================" | tee -a "$LOG_FILE"
echo "截图功能性能和稳定性测试" | tee -a "$LOG_FILE"
echo "开始时间: $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# 获取应用PID
get_app_pid() {
    ps aux | grep -i "$APP_NAME" | grep -v grep | awk '{print $2}'
}

# 获取内存使用 (MB)
get_memory_usage() {
    local pid=$1
    if [ -z "$pid" ]; then
        echo "N/A"
        return
    fi
    ps -p $pid -o rss= | awk '{print $1/1024 " MB"}'
}

# 获取CPU使用率
get_cpu_usage() {
    local pid=$1
    if [ -z "$pid" ]; then
        echo "N/A"
        return
    fi
    ps -p $pid -o %cpu= | awk '{print $1 "%"}'
}

# 记录系统状态
log_system_status() {
    local label=$1
    local pid=$(get_app_pid)
    echo "[$label] $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
    echo "  PID: $pid" | tee -a "$LOG_FILE"
    echo "  内存: $(get_memory_usage $pid)" | tee -a "$LOG_FILE"
    echo "  CPU: $(get_cpu_usage $pid)" | tee -a "$LOG_FILE"
}

# 测试1: 启动速度测试 (5次)
echo "" | tee -a "$LOG_FILE"
echo "========== 测试1: 启动速度测试 (5次) ==========" | tee -a "$LOG_FILE"
log_system_status "测试1开始前"

for i in {1..5}; do
    echo "" | tee -a "$LOG_FILE"
    echo "--- 第 $i 次测试 ---" | tee -a "$LOG_FILE"

    # 记录开始时间 (毫秒)
    START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")

    # 触发截图快捷键 (⌥⌘C)
    osascript -e 'tell application "System Events" to keystroke "c" using {option down, command down}'

    # 等待窗口出现
    sleep 0.5

    # 记录结束时间
    END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
    ELAPSED=$((END_TIME - START_TIME))

    echo "启动耗时: ${ELAPSED}ms" | tee -a "$LOG_FILE"
    echo "$i,${ELAPSED}" >> "$TIMING_LOG"

    # 记录资源使用
    log_system_status "第${i}次启动后"

    # 等待3秒再进行下一次
    sleep 3
done

# 测试2: 窗口检测性能测试
echo "" | tee -a "$LOG_FILE"
echo "========== 测试2: 窗口检测性能测试 ==========" | tee -a "$LOG_FILE"

# 统计当前窗口数
WINDOW_COUNT=$(osascript -e 'tell application "System Events" to count of processes whose background only is false' 2>/dev/null || echo "unknown")
echo "当前运行的应用数: $WINDOW_COUNT" | tee -a "$LOG_FILE"

# 检查debug日志中的窗口信息
if [ -f "$DEBUG_LOG" ]; then
    echo "窗口检测日志:" | tee -a "$LOG_FILE"
    grep "全局窗口数\|过滤后窗口数" "$DEBUG_LOG" | tail -20 | tee -a "$LOG_FILE"
fi

# 测试3: 内存稳定性测试 (连续触发10次)
echo "" | tee -a "$LOG_FILE"
echo "========== 测试3: 内存稳定性测试 (10次连续触发) ==========" | tee -a "$LOG_FILE"

log_system_status "内存测试开始前"

for i in {1..10}; do
    # 快速触发截图
    osascript -e 'tell application "System Events" to keystroke "c" using {option down, command down}'
    sleep 0.5

    # 取消截图 (ESC键)
    osascript -e 'tell application "System Events" to key code 53'

    # 记录内存
    local pid=$(get_app_pid)
    local memory=$(get_memory_usage $pid)
    echo "  第${i}次: 内存=$memory" | tee -a "$LOG_FILE"

    sleep 1
done

log_system_status "内存测试结束后"

# 测试4: 渲染性能分析 (检查debug日志中的时间戳)
echo "" | tee -a "$LOG_FILE"
echo "========== 测试4: 渲染性能分析 ==========" | tee -a "$LOG_FILE"

if [ -f "$DEBUG_LOG" ]; then
    # 分析日志中的时间间隔
    echo "日志分析结果:" | tee -a "$LOG_FILE"
    grep -E "开始过滤窗口|过滤完成" "$DEBUG_LOG" | head -40 | tee -a "$LOG_FILE"
fi

# 测试5: 边界情况测试
echo "" | tee -a "$LOG_FILE"
echo "========== 测试5: 边界情况检查 ==========" | tee -a "$LOG_FILE"

echo "检查debug日志中的错误和警告:" | tee -a "$LOG_FILE"
if [ -f "$DEBUG_LOG" ]; then
    grep -iE "error|warning|failed|⚠️" "$DEBUG_LOG" | tail -30 | tee -a "$LOG_FILE"
fi

# 最终状态
echo "" | tee -a "$LOG_FILE"
echo "========== 测试完成 ==========" | tee -a "$LOG_FILE"
log_system_status "最终状态"

# 生成统计报告
echo "" | tee -a "$LOG_FILE"
echo "========== 统计摘要 ==========" | tee -a "$LOG_FILE"

if [ -f "$TIMING_LOG" ]; then
    echo "启动耗时统计 (ms):" | tee -a "$LOG_FILE"
    awk -F, '{sum+=$2; count++} END {print "  平均: " (sum/count) " ms"; print "  总计: " count " 次"}' "$TIMING_LOG" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "日志文件位置:" | tee -a "$LOG_FILE"
echo "  $LOG_FILE" | tee -a "$LOG_FILE"
echo "  $TIMING_LOG" | tee -a "$LOG_FILE"
echo "  $DEBUG_LOG" | tee -a "$LOG_FILE"
