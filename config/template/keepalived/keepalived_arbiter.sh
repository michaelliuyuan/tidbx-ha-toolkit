#!/bin/bash
STATE_FILE="/tmp/keepalived_state"
# 检查文件是否存在
if [ ! -f "$STATE_FILE" ]; then
    # 文件不存在时，默认视为 BACKUP，退出码为 1
    exit 1
fi
# 读取文件内容并去除首尾空白字符
CONTENT=$(cat "$STATE_FILE" | tr -d '[:space:]')
# 根据内容决定退出码
if [ "$CONTENT" = "MASTER" ]; then
    echo "Status: MASTER"
    exit 0
else
    # 内容不是 MASTER（包括 BACKUP 或其它任何值）均视为非主状态
    echo "Status: BACKUP"
    exit 1
fi
