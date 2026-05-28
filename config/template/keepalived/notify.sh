#!/bin/bash
# 这是 Keepalived 的状态通知脚本
# 它的作用是将当前的角色 (MASTER/BACKUP/FAULT) 写入文件

TYPE=$1      # 通常是 "INSTANCE"
NAME=$2      # VRRP 实例的名称
STATE=$3     # 目标状态：MASTER, BACKUP, 或 FAULT

# 指定状态文件的路径
STATE_FILE="/tmp/keepalived_state"

# 将当前状态和实例名写入文件
echo "$STATE" > "$STATE_FILE"

# 可选：向系统日志发送一条消息，方便排查问题
logger "Keepalived: VRRP instance $NAME transitioned to $STATE state. State written to $STATE_FILE"
