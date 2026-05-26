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
section "  网络延迟测试"
section "=========================================="

section "--- 测试 1: 初始状态检查 ---"
INIT_MODE=$(get_replication_mode)
if [ "$INIT_MODE" = "sync" ]; then
    record_result "初始复制模式 SYNC" "PASS"
else
    record_result "初始复制模式 SYNC" "FAIL" "当前模式: ${INIT_MODE}"
fi

section "--- 测试 2: 1s 延迟（应保持 SYNC）---"
info "添加 1s 网络延迟 (${NODE_IP} → ${PEER_IP})..."
add_network_delay "$NODE_IP" "1s" "$NIC"
sleep 30

MODE_1S=$(get_replication_mode "$NODE_IP")
if [ "$MODE_1S" = "sync" ]; then
    record_result "1s 延迟下复制模式保持 SYNC" "PASS"
else
    record_result "1s 延迟下复制模式保持 SYNC" "FAIL" "实际: ${MODE_1S}"
fi

info "清除 1s 延迟..."
remove_network_delay "$NODE_IP" "$NIC"
sleep 10

section "--- 测试 3: 延迟清除后恢复验证 ---"
if wait_for_replication_state "sync" 60 "$NODE_IP"; then
    record_result "1s 延迟清除后复制恢复 SYNC" "PASS"
else
    record_result "1s 延迟清除后复制恢复 SYNC" "FAIL"
fi

section "--- 测试 4: 10s 延迟（应降级 ASYNC）---"
info "添加 10s 网络延迟 (${NODE_IP} → ${PEER_IP})..."
add_network_delay "$NODE_IP" "10s" "$NIC"
sleep 30

MODE_10S=$(get_replication_mode "$NODE_IP")
if [ "$MODE_10S" = "async" ]; then
    record_result "10s 延迟下复制模式降级 ASYNC" "PASS"
else
    record_result "10s 延迟下复制模式降级 ASYNC" "FAIL" "实际: ${MODE_10S}"
fi

info "清除 10s 延迟..."
remove_network_delay "$NODE_IP" "$NIC"

section "--- 测试 5: 10s 延迟清除后恢复 SYNC ---"
info "等待复制恢复 SYNC..."
if wait_for_replication_state "sync" 180 "$NODE_IP"; then
    record_result "10s 延迟清除后复制恢复 SYNC" "PASS"
else
    record_result "10s 延迟清除后复制恢复 SYNC" "FAIL" "超时 180s"
fi

generate_report
