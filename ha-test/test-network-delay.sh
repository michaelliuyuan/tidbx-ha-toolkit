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
if [ "$INIT_MODE" = "SYNC" ]; then
    record_result "初始复制模式 SYNC" "PASS"
else
    record_result "初始复制模式 SYNC" "FAIL" "当前模式: ${INIT_MODE}"
fi

section "--- 测试 2: 1s 延迟（应保持 SYNC，最多重试6次每次10秒）---"
mark_phase "delay_1s" "start"
info "添加 1s 网络延迟 (${NODE_IP} → ${PEER_IP})..."
add_network_delay "$NODE_IP" "1s" "$NIC"

MODE_1S=$(wait_for_async_with_retry "SYNC" "$NODE_IP" 6 10 || true)
if [ "$MODE_1S" = "SYNC" ]; then
    record_result "1s 延迟下复制模式保持 SYNC" "PASS"
else
    record_result "1s 延迟下复制模式保持 SYNC" "FAIL" "实际: ${MODE_1S}"
fi
snapshot_concurrent_stats "delay_1s_after"
mark_phase "delay_1s" "end"

info "清除 1s 延迟..."
remove_network_delay "$NODE_IP" "$NIC"
sleep 10

section "--- 测试 3: 延迟清除后恢复验证 ---"
if wait_for_replication_state "SYNC" 60 "$NODE_IP"; then
    record_result "1s 延迟清除后复制恢复 SYNC" "PASS"
else
    record_result "1s 延迟清除后复制恢复 SYNC" "FAIL"
fi

section "--- 测试 4: 10s 延迟（应降级 ASYNC）---"
mark_phase "delay_10s" "start"
snapshot_concurrent_stats "delay_10s_before"
info "添加 10s 网络延迟 (${NODE_IP} → ${PEER_IP})..."
add_network_delay "$NODE_IP" "10s" "$NIC"
sleep 30

MODE_10S=$(wait_for_async_with_retry "ASYNC" "$NODE_IP" 10 10 || true)
if [ "$MODE_10S" = "ASYNC" ]; then
    record_result "10s 延迟下复制模式降级 ASYNC" "PASS"
else
    record_result "10s 延迟下复制模式降级 ASYNC" "FAIL" "实际: ${MODE_10S}"
fi
snapshot_concurrent_stats "delay_10s_after"
mark_phase "delay_10s" "end"

info "清除 10s 延迟..."
remove_network_delay "$NODE_IP" "$NIC"

section "--- 测试 5: 10s 延迟清除后恢复 SYNC ---"
info "等待复制恢复 SYNC..."
if wait_for_replication_state "SYNC" 180 "$NODE_IP"; then
    record_result "10s 延迟清除后复制恢复 SYNC" "PASS"
else
    record_result "10s 延迟清除后复制恢复 SYNC" "FAIL" "超时 180s"
fi

section "--- 测试 6: 网络完全隔离（应降级 ASYNC）---"
mark_phase "network_isolation" "start"
snapshot_concurrent_stats "network_isolation_before"
info "模拟两节点网络完全隔离 (iptables)..."
ssh_exec "$NODE_IP" "${SUDO} iptables -A OUTPUT -d ${PEER_IP} -j DROP" 2>/dev/null
ssh_exec "$PEER_IP" "${SUDO} iptables -A OUTPUT -d ${NODE_IP} -j DROP" 2>/dev/null

MODE_ISO=$(wait_for_async_with_retry "ASYNC" "$NODE_IP" 6 10 || true)
if [ "$MODE_ISO" = "ASYNC" ]; then
    record_result "网络隔离后复制模式降级 ASYNC" "PASS"
else
    record_result "网络隔离后复制模式降级 ASYNC" "FAIL" "实际: ${MODE_ISO}"
fi
snapshot_concurrent_stats "network_isolation_after"
mark_phase "network_isolation" "end"

info "清除网络隔离..."
ssh_exec "$NODE_IP" "${SUDO} iptables -D OUTPUT -d ${PEER_IP} -j DROP" 2>/dev/null
ssh_exec "$PEER_IP" "${SUDO} iptables -D OUTPUT -d ${NODE_IP} -j DROP" 2>/dev/null

section "--- 测试 7: 网络隔离恢复后恢复 SYNC ---"
info "等待复制恢复 SYNC..."
if wait_for_replication_state "SYNC" 180 "$NODE_IP"; then
    record_result "网络隔离恢复后复制恢复 SYNC" "PASS"
else
    record_result "网络隔离恢复后复制恢复 SYNC" "FAIL" "超时 180s"
fi

generate_report
