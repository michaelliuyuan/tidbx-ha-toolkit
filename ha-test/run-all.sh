#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE=""
BUSINESS_DURATION=600
CONCURRENCY=10

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        --duration) BUSINESS_DURATION="$2"; shift 2 ;;
        --concurrency) CONCURRENCY="$2"; shift 2 ;;
        --help|-h)
            echo "用法: $0 --env <config.env> [--duration <seconds>] [--concurrency <N>]"
            echo ""
            echo "运行全部 HA 测试场景（含并发业务模拟）："
            echo "  1. 环境预检"
            echo "  2. 启动并发业务模拟"
            echo "  3. 节点重启测试"
            echo "  4. 网络延迟测试"
            echo "  5. 数据损坏测试"
            echo "  6. 停止业务模拟并生成报告"
            echo ""
            echo "选项:"
            echo "  --env          配置文件"
            echo "  --duration     业务模拟时长 (秒, 默认 600)"
            echo "  --concurrency  并发连接数 (默认 10)"
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
section "  并发数: ${CONCURRENCY}"
section "=============================================="

section "=== 阶段 0: 环境预检 ==="
if ! bash "${PROJECT_DIR}/deploy/verify.sh" --env "$ENV_FILE"; then
    error "环境预检失败，请检查集群状态"
    exit 1
fi

section "=== 阶段 1: 启动 ${CONCURRENCY} 并发业务模拟 ==="
start_concurrent_load "$BUSINESS_DURATION" "$CONCURRENCY"

section "=== 阶段 2: 节点重启测试 ==="
bash "${SCRIPT_DIR}/test-node-restart.sh" --env "$ENV_FILE"

section "=== 阶段 3: 网络延迟测试 ==="
bash "${SCRIPT_DIR}/test-network-delay.sh" --env "$ENV_FILE"

section "=== 阶段 4: 数据损坏测试 ==="
bash "${SCRIPT_DIR}/test-data-corrupt.sh" --env "$ENV_FILE"

section "=== 阶段 5: 停止业务模拟 ==="
stop_concurrent_load

section "=== 阶段 6: 数据一致性检查 ==="
CONSISTENCY_RESULT=$(check_data_consistency)
info "数据一致性检查结果:"
cat "$CONSISTENCY_RESULT"

section "=== 阶段 7: 生成测试报告 ==="

IMPACT_FILE=$(compute_impact_stats)
info "每个测试场景业务影响统计:"
cat "$IMPACT_FILE"

TOTAL_OPS=0 SUCCESS_OPS=0 FAIL_OPS=0
for wf in "${BUSINESS_LOAD_DIR}"/worker_*.csv; do
    [ -f "$wf" ] || continue
    t=$(tail -n +2 "$wf" | wc -l)
    s=$(tail -n +2 "$wf" | grep -c ',1,' 2>/dev/null || echo "0")
    f=$(tail -n +2 "$wf" | grep -c ',0,' 2>/dev/null || echo "0")
    TOTAL_OPS=$((TOTAL_OPS + t))
    SUCCESS_OPS=$((SUCCESS_OPS + s))
    FAIL_OPS=$((FAIL_OPS + f))
done

FINAL_REPORT="${TEST_RESULTS_DIR}/ha_test_report_$(date +%Y%m%d_%H%M%S).md"

cat > "$FINAL_REPORT" <<EOF
# HA 测试报告

**测试时间**: $(date '+%Y-%m-%d %H:%M:%S')
**节点 1 (Master)**: ${NODE_IP}
**节点 2 (Backup)**: ${PEER_IP}
**VIP**: ${VIP}
**并发业务数**: ${CONCURRENCY}

## 测试结果汇总

| 项目 | 结果 |
|------|------|
| 总测试数 | ${TOTAL_TESTS} |
| 通过 | ${PASSED_TESTS} |
| 失败 | ${FAILED_TESTS} |

## 并发业务统计

| 指标 | 值 |
|------|------|
| 总操作数 | ${TOTAL_OPS} |
| 成功操作 | ${SUCCESS_OPS} |
| 失败操作 | ${FAIL_OPS} |
| 成功率 | $(awk "BEGIN{if(${TOTAL_OPS}>0) printf \"%.2f%%\",${SUCCESS_OPS}*100/${TOTAL_OPS}; else print \"N/A\"}") |

## 数据一致性检查

\`\`\`
$(cat "$CONSISTENCY_RESULT")
\`\`\`

## 每个测试场景的业务影响

\`\`\`
$(cat "$IMPACT_FILE")
\`\`\`

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
