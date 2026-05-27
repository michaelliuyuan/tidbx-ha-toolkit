#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

ENV_FILE=""
REMOVE_DATA=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        --remove-data) REMOVE_DATA=true; shift ;;
        --help|-h)
            echo "用法: $0 --env <config.env> [--remove-data]"
            echo "  --remove-data  同时删除数据目录 /data/tidb"
            exit 0 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

NODE_ROLE="${NODE_ROLE:-master}"

info "停止 Docker Compose 容器..."
if [ "$NODE_ROLE" = "master" ]; then
    COMPOSE_FILE="${PROJECT_DIR}/docker-compose_node1.generated.yml"
else
    COMPOSE_FILE="${PROJECT_DIR}/docker-compose_node2.generated.yml"
fi

if [ -f "$COMPOSE_FILE" ]; then
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down 2>/dev/null || true
    info "Docker Compose 容器已停止"
fi

info "停止 Keepalived..."
systemctl stop keepalived 2>/dev/null || true
systemctl disable keepalived 2>/dev/null || true

if [ "$REMOVE_DATA" = true ]; then
    warn "删除数据目录 /data/tidb ..."
    rm -rf /data/tidb
    rm -rf /data/scripts
    rm -rf /tmp/keepalived_state
    info "数据目录已清理"
fi

rm -f "${PROJECT_DIR}/docker-compose_node1.generated.yml"
rm -f "${PROJECT_DIR}/docker-compose_node2.generated.yml"

info "清理完成 ✅"
