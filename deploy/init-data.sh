#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        --help|-h) echo "用法: $0 --env <config.env>"; exit 0 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
    echo "错误: 请指定 --env <config.env>"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

DATA_DIR="/data/tidb"
SCRIPTS_DIR="/data/scripts"

echo "=== 初始化数据目录 ==="
mkdir -p "${DATA_DIR}/etc"
mkdir -p "${DATA_DIR}/var/pd/data"
mkdir -p "${DATA_DIR}/var/pd/log"
mkdir -p "${DATA_DIR}/var/tikv/data"
mkdir -p "${DATA_DIR}/var/tikv/log"
mkdir -p "${DATA_DIR}/var/tidb/log"
mkdir -p "${SCRIPTS_DIR}"
mkdir -p "/tmp/keepalived_state"

echo "=== 生成配置文件 ==="
envsubst < "${PROJECT_DIR}/config/template/pd.toml" > "${DATA_DIR}/etc/pd.toml"
envsubst < "${PROJECT_DIR}/config/template/tikv.toml" > "${DATA_DIR}/etc/tikv.toml"
envsubst < "${PROJECT_DIR}/config/template/tidb.toml" > "${DATA_DIR}/etc/tidb.toml"

echo "=== 复制探活脚本 ==="
cp "${PROJECT_DIR}/config/template/keepalived/keepalived_arbiter.sh" "${SCRIPTS_DIR}/keepalived_arbiter.sh"
chmod +x "${SCRIPTS_DIR}/keepalived_arbiter.sh"

echo "=== 生成 Docker Compose 文件 ==="
envsubst < "${PROJECT_DIR}/config/docker-compose/docker-compose_node1.yml" > "${PROJECT_DIR}/docker-compose_node1.generated.yml"
envsubst < "${PROJECT_DIR}/config/docker-compose/docker-compose_node2.yml" > "${PROJECT_DIR}/docker-compose_node2.generated.yml"

echo "=== 数据目录初始化完成 ==="
echo "  配置文件: ${DATA_DIR}/etc/"
echo "  数据目录: ${DATA_DIR}/var/"
echo "  脚本目录: ${SCRIPTS_DIR}/"
