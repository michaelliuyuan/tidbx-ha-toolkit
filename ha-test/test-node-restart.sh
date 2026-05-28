#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        --help|-h) echo "用法: $0 --env <config.env>"; exit 0 ;;
        *) error "未知参数: $1"; exit 1 ;;
    esac
done

init_test_env "$ENV_FILE"

section "=========================================="
section "  节点重启测试"
section "=========================================="

section "--- 测试 1: 初始状态检查 ---"
INIT_MODE=$(get_replication_mode)
if [ "$INIT_MODE" = "SYNC" ]; then
    record_result "初始复制模式 SYNC" "PASS"
else
    record_result "初始复制模式 SYNC" "FAIL" "当前模式: ${INIT_MODE}"
fi

section "--- 测试 2: Master 节点关机 ---"
info "关闭 Master 节点 (${NODE_IP})..."
stop_node "$NODE_IP"
sleep 10

VIP_MOVED=false
if check_vip_on_node "$PEER_IP"; then
    record_result "VIP 漂移到 Backup" "PASS"
    VIP_MOVED=true
else
    record_result "VIP 漂移到 Backup" "FAIL" "VIP 未在 Backup 节点上"
fi

MODE_AFTER_MASTER_DOWN=$(wait_for_async_with_retry "ASYNC" "$PEER_IP" 10 10 || true)
if [ "$MODE_AFTER_MASTER_DOWN" = "ASYNC" ]; then
    record_result "Master 关机后复制模式 ASYNC" "PASS"
else
    record_result "Master 关机后复制模式 ASYNC" "FAIL" "实际: ${MODE_AFTER_MASTER_DOWN}"
fi

if check_mysql_via_vip; then
    record_result "Master 关机期间 MySQL 可用" "PASS"
else
    record_result "Master 关机期间 MySQL 可用" "FAIL"
fi

section "--- 测试 3: Master 节点恢复 ---"
info "启动 Master 节点 (${NODE_IP})..."
start_node "$NODE_IP"
info "等待集群恢复..."
sleep 30

if wait_for_replication_state "SYNC" 180 "$NODE_IP"; then
    record_result "Master 恢复后复制模式恢复 SYNC" "PASS"
else
    record_result "Master 恢复后复制模式恢复 SYNC" "FAIL" "超时 180s 未恢复"
fi

section "--- 测试 4: Backup 节点关机 ---"
info "关闭 Backup 节点 (${PEER_IP})..."
stop_node "$PEER_IP"
sleep 15

MODE_AFTER_BACKUP_DOWN=$(wait_for_async_with_retry "ASYNC" "$NODE_IP" 10 10 || true)
if [ "$MODE_AFTER_BACKUP_DOWN" = "ASYNC" ]; then
    record_result "Backup 关机后复制模式 ASYNC" "PASS"
else
    record_result "Backup 关机后复制模式 ASYNC" "FAIL" "实际: ${MODE_AFTER_BACKUP_DOWN}"
fi

if check_mysql_via_vip; then
    record_result "Backup 关机期间 MySQL 可用 (VIP)" "PASS"
else
    record_result "Backup 关机期间 MySQL 可用" "FAIL"
fi

section "--- 测试 5: Backup 节点恢复 ---"
info "启动 Backup 节点 (${PEER_IP})..."
start_node "$PEER_IP"
info "等待集群恢复..."
sleep 30

if wait_for_replication_state "SYNC" 180 "$NODE_IP"; then
    record_result "Backup 恢复后复制模式恢复 SYNC" "PASS"
else
    record_result "Backup 恢复后复制模式恢复 SYNC" "FAIL" "超时 180s 未恢复"
fi

generate_report
