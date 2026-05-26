#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

ENV_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        --help|-h)
            echo "用法: $0 --env <config.env>"
            exit 0 ;;
        *) error "未知参数: $1"; exit 1 ;;
    esac
done

if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
    error "请指定 --env <config.env>"
    exit 1
fi

source "$ENV_FILE"

if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 用户或 sudo 执行此脚本"
    exit 1
fi

NIC="${NIC:-ens33}"
VIP="${VIP:-}"
VIP_PREFIX="${VIP_PREFIX:-24}"
KEEPALIVED_PRIORITY="${KEEPALIVED_PRIORITY:-100}"
KEEPALIVED_AUTH_PASS="${KEEPALIVED_AUTH_PASS:-123456}"
KEEPALIVED_VRID="${KEEPALIVED_VRID:-51}"
NODE_ROLE="${NODE_ROLE:-master}"
NODE_IP="${NODE_IP:-}"
PEER_IP="${PEER_IP:-}"

if [ -z "$VIP" ] || [ -z "$NODE_IP" ] || [ -z "$PEER_IP" ]; then
    error "缺少必要配置: VIP, NODE_IP, PEER_IP"
    exit 1
fi

info "安装 Keepalived..."
if command -v yum &>/dev/null; then
    yum install -y keepalived
elif command -v apt-get &>/dev/null; then
    apt-get update && apt-get install -y keepalived
fi

info "配置 Keepalived (${NODE_ROLE}, priority=${KEEPALIVED_PRIORITY})..."

NOTIFY_SCRIPT="/data/scripts/notify.sh"
cp "${PROJECT_DIR}/config/template/keepalived/notify.sh" "$NOTIFY_SCRIPT"
chmod +x "$NOTIFY_SCRIPT"

KEEPALIVED_STATE="MASTER"
KEEPALIVED_PEER=""
if [ "$NODE_ROLE" = "backup" ]; then
    KEEPALIVED_STATE="BACKUP"
fi

mkdir -p /etc/keepalived

cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id TIDBX_HA_${NODE_ROLE^^}
    script_user root
    enable_script_security
}

vrrp_script check_tidb {
    script "/data/scripts/keepalived_arbiter.sh"
    interval 3
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_${KEEPALIVED_VRID} {
    state ${KEEPALIVED_STATE}
    interface ${NIC}
    virtual_router_id ${KEEPALIVED_VRID}
    priority ${KEEPALIVED_PRIORITY}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass ${KEEPALIVED_AUTH_PASS}
    }
    virtual_ipaddress {
        ${VIP}/${VIP_PREFIX} dev ${NIC}
    }
    track_script {
        check_tidb
    }
    notify "${NOTIFY_SCRIPT}"
}
EOF

systemctl enable keepalived
systemctl restart keepalived

info "Keepalived 配置完成 (角色: ${NODE_ROLE}, VIP: ${VIP}) ✅"
