#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

ACTION=""
BUSINESS_DURATION=600
BUSINESS_CONCURRENCY=10

usage() {
    echo "用法: $0 <start|stop|status> --env <config.env> [--duration <seconds>] [--concurrency <N>]"
    echo ""
    echo "命令:"
    echo "  start    启动并发业务模拟"
    echo "  stop     停止并发业务模拟"
    echo "  status   查看业务模拟状态"
    echo ""
    echo "选项:"
    echo "  --env          配置文件"
    echo "  --duration     运行时长 (秒, 默认 600)"
    echo "  --concurrency  并发数 (默认 10)"
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
        --env) ENV_FILE="$2"; shift 2 ;;
        --duration) BUSINESS_DURATION="$2"; shift 2 ;;
        --concurrency) BUSINESS_CONCURRENCY="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

start_cmd() {
    if check_concurrent_load_running; then
        warn "并发业务模拟已在运行"
        exit 0
    fi

    if [ -z "${VIP:-}" ]; then
        error "VIP 未设置，请通过 --env 指定配置文件"
        exit 1
    fi

    start_concurrent_load "$BUSINESS_DURATION" "$BUSINESS_CONCURRENCY"
}

stop_cmd() {
    stop_concurrent_load
}

status_cmd() {
    if check_concurrent_load_running; then
        info "并发业务模拟运行中"
        local alive=0
        while read -r pid; do
            [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=$((alive + 1))
        done < "${BUSINESS_LOAD_DIR}/workers.pid"
        info "活跃 worker 数: ${alive}"

        local total_ops=0 success_ops=0 fail_ops=0
        for wf in "${BUSINESS_LOAD_DIR}"/worker_*.csv; do
            [ -f "$wf" ] || continue
            local t s f
            t=$(tail -n +2 "$wf" | wc -l)
            s=$(tail -n +2 "$wf" | grep -c ',1,' 2>/dev/null || echo "0")
            f=$(tail -n +2 "$wf" | grep -c ',0,' 2>/dev/null || echo "0")
            total_ops=$((total_ops + t))
            success_ops=$((success_ops + s))
            fail_ops=$((fail_ops + f))
        done
        info "总操作: ${total_ops}, 成功: ${success_ops}, 失败: ${fail_ops}"
    else
        info "并发业务模拟未在运行"
    fi
}

case "$ACTION" in
    start)  start_cmd ;;
    stop)   stop_cmd ;;
    status) status_cmd ;;
    *)      usage; exit 1 ;;
esac
