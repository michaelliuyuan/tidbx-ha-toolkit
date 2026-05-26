#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE=""
BUSINESS_DURATION=600

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        --duration) BUSINESS_DURATION="$2"; shift 2 ;;
        --help|-h)
            echo "用法: $0 --env <config.env> [--duration <seconds>]"
            echo ""
            echo "运行全部 HA 测试场景:"
            echo "  1. 节点重启测试"
            echo "  2. 网络延迟测试"
            echo "  3. 数据损坏测试"
            echo "  4. 业务模拟 + 故障注入"
            exit 0 ;;
        *) error "未知参数: $1"; exit 1 ;;
    esac
done

init_test_env "$ENV_FILE"

section "=============================================="
section "  tidbx-ha-toolkit 全量 HA 测试"
section "  $(date '+%Y-%m-%d %H:%M:%S')"
section "  Node1: ${NODE_IP}"
section "  Node2: ${PEER_IP}"
section "  VIP: ${VIP}"
section "=============================================="

section "=== 阶段 0: 环境预检 ==="
bash "${PROJECT_DIR}/deploy/verify.sh" --env "$ENV_FILE"
if [ $? -ne 0 ]; then
    error "环境预检失败，请检查集群状态"
    exit 1
fi

section "=== 阶段 1: 启动业务模拟 ==="
bash "${SCRIPT_DIR}/test-business.sh" start --vip "$VIP" --duration "$BUSINESS_DURATION" --env "$ENV_FILE"
info "业务模拟已启动，持续 ${BUSINESS_DURATION}s"

section "=== 阶段 2: 节点重启测试 ==="
bash "${SCRIPT_DIR}/test-node-restart.sh" --env "$ENV_FILE"

section "=== 阶段 3: 网络延迟测试 ==="
bash "${SCRIPT_DIR}/test-network-delay.sh" --env "$ENV_FILE"

section "=== 阶段 4: 数据损坏测试 ==="
bash "${SCRIPT_DIR}/test-data-corrupt.sh" --env "$ENV_FILE"

section "=== 阶段 5: 停止业务模拟 ==="
bash "${SCRIPT_DIR}/test-business.sh" stop

section "=== 生成测试报告 ==="

QPS_FILE="${TEST_RESULTS_DIR}/business_qps.log"
if [ -f "$QPS_FILE" ]; then
    TOTAL_OPS=$(tail -n +2 "$QPS_FILE" | wc -l)
    SUCCESS_OPS=$(tail -n +2 "$QPS_FILE" | grep -c ",1," 2>/dev/null || echo "0")
    FAIL_OPS=$(tail -n +2 "$QPS_FILE" | grep -c ",0," 2>/dev/null || echo "0")
else
    TOTAL_OPS=0; SUCCESS_OPS=0; FAIL_OPS=0
fi

FINAL_REPORT="${TEST_RESULTS_DIR}/ha_test_report_$(date +%Y%m%d_%H%M%S).md"

cat > "$FINAL_REPORT" <<EOF
# HA 测试报告

**测试时间**: $(date '+%Y-%m-%d %H:%M:%S')
**节点 1 (Master)**: ${NODE_IP}
**节点 2 (Backup)**: ${PEER_IP}
**VIP**: ${VIP}

## 测试结果汇总

| 项目 | 结果 |
|------|------|
| 总测试数 | ${TOTAL_TESTS} |
| 通过 | ${PASSED_TESTS} |
| 失败 | ${FAILED_TESTS} |

## 业务模拟统计

| 指标 | 值 |
|------|------|
| 总操作数 | ${TOTAL_OPS} |
| 成功操作 | ${SUCCESS_OPS} |
| 失败操作 | ${FAIL_OPS} |
| 成功率 | $(awk "BEGIN{if(${TOTAL_OPS}>0) printf \"%.2f%%\",${SUCCESS_OPS}*100/${TOTAL_OPS}; else print \"N/A\"}") |

## 详细结果

$(cat "${TEST_RESULTS_DIR}/details.log" 2>/dev/null || echo "无详细日志")

---
报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF

info "测试报告已生成: ${FINAL_REPORT}"
cat "$FINAL_REPORT"

generate_report

if [ "$FAILED_TESTS" -gt 0 ]; then
    exit 1
fi
