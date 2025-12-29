#!/bin/bash

# Quite Note 自动构建监视脚本
# 监听 Sources 目录的变化并触发构建

echo "👀 开始监视 Sources 目录变化..."

# 记录上次构建时间
LAST_BUILD_TIME=0
# 冷却时间（秒），防止频繁触发
COOLDOWN=3

while true; do
    # 查找 Sources 目录下最近修改的文件时间戳
    CURRENT_MOD_TIME=$(find Sources -type f -exec stat -f "%m" {} + | sort -rn | head -1)
    
    if [ "$CURRENT_MOD_TIME" -gt "$LAST_BUILD_TIME" ]; then
        NOW=$(date +%s)
        if [ $((NOW - LAST_BUILD_TIME)) -gt $COOLDOWN ]; then
            echo "✨ 检测到代码变化，开始构建..."
            ./build-app.sh
            LAST_BUILD_TIME=$NOW
            echo "✅ 构建完成，继续监视..."
        fi
    fi
    sleep 2
done
