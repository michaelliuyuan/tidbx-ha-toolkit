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
section "  数据损坏测试"
section "=========================================="

section "--- 测试 1: 初始状态检查 ---"
INIT_MODE=$(get_replication_mode)
if [ "$INIT_MODE" = "SYNC" ]; then
    record_result "初始复制模式 SYNC" "PASS"
else
    record_result "初始复制模式 SYNC" "FAIL" "当前模式: ${INIT_MODE}"
fi

section "--- 测试 2: 删除 Backup TiKV 数据 ---"
mark_phase "data_corrupt" "start"
snapshot_concurrent_stats "data_corrupt_before"
info "删除 Backup (${PEER_IP}) TiKV 数据目录..."
ssh_exec "$PEER_IP" "${SUDO} docker exec \$(${SUDO} docker ps -q) ls /var/lib/data/tikv/data/" 2>/dev/null || true
ssh_exec "$PEER_IP" "${SUDO} docker exec \$(${SUDO} docker ps -q) rm -rf /var/lib/data/tikv/data/*" 2>/dev/null || true

info "等待集群响应..."
sleep 30

MODE_AFTER_CORRUPT=$(get_replication_mode "$NODE_IP")
if [ "$MODE_AFTER_CORRUPT" = "ASYNC" ]; then
    record_result "Backup 数据损坏后复制模式变为 ASYNC" "PASS"
else
    record_result "Backup 数据损坏后复制模式变为 ASYNC" "WARN" "实际: ${MODE_AFTER_CORRUPT}"
fi
snapshot_concurrent_stats "data_corrupt_after"
mark_phase "data_corrupt" "end"

section "--- 测试 3: Master 端 TiDB 可用性 ---"
if check_mysql_via_vip; then
    record_result "数据损坏后 Master TiDB 可用" "PASS"
else
    record_result "数据损坏后 Master TiDB 可用" "FAIL"
fi

section "--- 测试 4: 重置 Backup 节点 ---"
info "重置 Backup 节点..."
ssh_exec "$PEER_IP" "${SUDO} systemctl stop keepalived; ${SUDO} docker stop \$(${SUDO} docker ps -q) 2>/dev/null || true"
sleep 5
ssh_exec "$PEER_IP" "${SUDO} rm -rf /data/tidb/var/tikv/data/*"
info "需要手动重新部署 Backup 节点来恢复集群"
record_result "Backup 节点数据清理" "PASS" "Backup 已清理，需重新部署"

generate_report
