#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
PASS=0; FAIL=0

ENV_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        --help|-h) echo "用法: $0 --env <config.env>"; exit 0 ;;
        *) error "未知参数: $1"; exit 1 ;;
    esac
done

if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
    error "请指定 --env <config.env>"
    exit 1
fi

source "$ENV_FILE"

NODE_IP="${NODE_IP:-}"
PEER_IP="${PEER_IP:-}"
VIP="${VIP:-}"
PD_CLI_PORT="${PD_CLI_PORT:-2379}"
TIDB_PORT="${TIDB_PORT:-4000}"

run_check() {
    local name="$1"
    shift
    if "$@" 2>/dev/null; then
        info "  ✅ ${name}"
        PASS=$((PASS + 1))
    else
        error "  ❌ ${name}"
        FAIL=$((FAIL + 1))
    fi
}

info "=== 集群状态验证 ==="

info "1. Docker 容器状态"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "tidb"; then
    info "  ✅ TiDB 容器运行中"
    PASS=$((PASS + 1))
else
    error "  ❌ TiDB 容器未运行"
    FAIL=$((FAIL + 1))
fi

info "2. PD 健康检查"
pd_ok=false
for ip in "$NODE_IP" "$PEER_IP"; do
    if curl -sf "http://${ip}:${PD_CLI_PORT}/health" 2>/dev/null | grep -q "true"; then
        pd_ok=true
        break
    fi
done
if $pd_ok; then
    info "  ✅ PD 健康"
    PASS=$((PASS + 1))
else
    error "  ❌ PD 不健康"
    FAIL=$((FAIL + 1))
fi

info "3. 复制模式"
REPL_STATE=$(curl -sf "http://${NODE_IP}:${PD_CLI_PORT}/pd/api/v1/replication_mode/status" 2>/dev/null || echo "{}")
if echo "$REPL_STATE" | grep -q "SYNC"; then
    info "  ✅ 复制模式: SYNC"
    PASS=$((PASS + 1))
elif echo "$REPL_STATE" | grep -q "ASYNC"; then
    warn "  ⚠️  复制模式: ASYNC（可能正在恢复中）"
    PASS=$((PASS + 1))
else
    error "  ❌ 无法获取复制模式"
    FAIL=$((FAIL + 1))
fi

info "4. MySQL 连接 (VIP)"
if [ -n "$VIP" ]; then
    if command -v mysql &>/dev/null; then
        if mysql -h "$VIP" -P "$TIDB_PORT" -u root -e "SELECT 1" &>/dev/null; then
            info "  ✅ VIP MySQL 连接正常 (${VIP}:${TIDB_PORT})"
            PASS=$((PASS + 1))
        else
            error "  ❌ VIP MySQL 连接失败"
            FAIL=$((FAIL + 1))
        fi
    else
        if nc -z -w3 "$VIP" "$TIDB_PORT" 2>/dev/null; then
            info "  ✅ VIP 端口可达 (${VIP}:${TIDB_PORT})"
            PASS=$((PASS + 1))
        else
            error "  ❌ VIP 端口不可达"
            FAIL=$((FAIL + 1))
        fi
    fi
fi

info "5. VIP 可达性"
if ping -c 1 -W 2 "$VIP" &>/dev/null; then
    info "  ✅ VIP (${VIP}) 可达"
    PASS=$((PASS + 1))
else
    error "  ❌ VIP (${VIP}) 不可达"
    FAIL=$((FAIL + 1))
fi

info "6. Keepalived 状态"
if systemctl is-active --quiet keepalived 2>/dev/null; then
    info "  ✅ Keepalived 运行中"
    PASS=$((PASS + 1))
else
    error "  ❌ Keepalived 未运行"
    FAIL=$((FAIL + 1))
fi

info ""
info "=== 验证结果: ${PASS} PASS, ${FAIL} FAIL ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
