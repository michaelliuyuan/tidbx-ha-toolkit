#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

ACTION=""
BUSINESS_VIP=""
BUSINESS_DURATION=300
BUSINESS_LOG=""

usage() {
    echo "用法: $0 <start|stop|status> --vip <VIP> [--duration <seconds>]"
    echo ""
    echo "命令:"
    echo "  start    启动业务模拟"
    echo "  stop     停止业务模拟"
    echo "  status   查看业务模拟状态"
    echo ""
    echo "选项:"
    echo "  --vip       VIP 地址"
    echo "  --duration  运行时长 (秒, 默认 300)"
    echo "  --env       配置文件"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

ACTION="$1"
shift

ENV_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --vip) BUSINESS_VIP="$2"; shift 2 ;;
        --duration) BUSINESS_DURATION="$2"; shift 2 ;;
        --env) ENV_FILE="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

BUSINESS_VIP="${BUSINESS_VIP:-${VIP:-}}"
TIDB_PORT="${TIDB_PORT:-4000}"
PID_FILE="/tmp/tidbx_business_test.pid"
LOG_FILE="${SCRIPT_DIR}/results/business_test.log"
QPS_FILE="${SCRIPT_DIR}/results/business_qps.log"

mkdir -p "${SCRIPT_DIR}/results"

start_business() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            warn "业务模拟已在运行 (PID: ${pid})"
            exit 0
        fi
        rm -f "$PID_FILE"
    fi

    if [ -z "$BUSINESS_VIP" ]; then
        error "请指定 --vip 参数"
        exit 1
    fi

    info "启动业务模拟: VIP=${BUSINESS_VIP}, 时长=${BUSINESS_DURATION}s"

    (
        echo "timestamp,operation,success,latency_ms" > "$QPS_FILE"

        if command -v mysql &>/dev/null; then
            mysql -h "$BUSINESS_VIP" -P "$TIDB_PORT" -u root -e "
                CREATE DATABASE IF NOT EXISTS ha_test;
                USE ha_test;
                CREATE TABLE IF NOT EXISTS ha_test (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    val VARCHAR(100),
                    ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            " 2>/dev/null
        fi

        local count=0
        local errors=0
        local start_time
        start_time=$(date +%s)

        while true; do
            local now
            now=$(date +%s)
            if [ $((now - start_time)) -ge "$BUSINESS_DURATION" ]; then
                break
            fi

            local ts
            ts=$(date '+%Y-%m-%d %H:%M:%S.%3N')
            local start_ms
            start_ms=$(date +%s%3N 2>/dev/null || echo "0")

            if command -v mysql &>/dev/null; then
                local val="ha_test_$(date +%s)_${RANDOM}"
                if mysql -h "$BUSINESS_VIP" -P "$TIDB_PORT" -u root -e "
                    USE ha_test;
                    INSERT INTO ha_test (val) VALUES ('${val}');
                " &>/dev/null; then
                    local end_ms
                    end_ms=$(date +%s%3N 2>/dev/null || echo "0")
                    local latency=$((end_ms - start_ms))
                    echo "${ts},INSERT,1,${latency}" >> "$QPS_FILE"
                else
                    echo "${ts},INSERT,0,0" >> "$QPS_FILE"
                    ((errors++))
                fi
            else
                if nc -z -w3 "$BUSINESS_VIP" "$TIDB_PORT" 2>/dev/null; then
                    echo "${ts},CHECK,1,0" >> "$QPS_FILE"
                else
                    echo "${ts},CHECK,0,0" >> "$QPS_FILE"
                    ((errors++))
                fi
            fi

            ((count++))
            sleep 0.1
        done

        info "业务模拟完成: 总操作=${count}, 错误=${errors}"
    ) &

    echo $! > "$PID_FILE"
    info "业务模拟已启动 (PID: $(cat "$PID_FILE"))"
}

stop_business() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            info "业务模拟已停止 (PID: ${pid})"
        fi
        rm -f "$PID_FILE"
    else
        warn "业务模拟未在运行"
    fi
}

status_business() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            info "业务模拟运行中 (PID: ${pid})"
            if [ -f "$QPS_FILE" ]; then
                local total successes failures
                total=$(tail -n +2 "$QPS_FILE" | wc -l)
                successes=$(tail -n +2 "$QPS_FILE" | grep -c ",1," 2>/dev/null || echo "0")
                failures=$(tail -n +2 "$QPS_FILE" | grep -c ",0," 2>/dev/null || echo "0")
                info "操作: ${total} 成功: ${successes} 失败: ${failures}"
            fi
            exit 0
        fi
    fi
    info "业务模拟未在运行"
}

case "$ACTION" in
    start)  start_business ;;
    stop)   stop_business ;;
    status) status_business ;;
    *)      usage; exit 1 ;;
esac
