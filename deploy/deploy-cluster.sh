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
error() { echo -e "${RED}[ERROR]${NC} $*"; }

ENV_FILE=""
OFFLINE_DIR=""
SKIP_DOCKER=false
SKIP_KEEPALIVED=false
SKIP_LOAD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        --offline-dir) OFFLINE_DIR="$2"; shift 2 ;;
        --skip-docker) SKIP_DOCKER=true; shift ;;
        --skip-keepalived) SKIP_KEEPALIVED=true; shift ;;
        --skip-load) SKIP_LOAD=true; shift ;;
        --help|-h)
            echo "用法: $0 --env <config.env> [--offline-dir <dir>] [--skip-docker] [--skip-keepalived] [--skip-load]"
            echo ""
            echo "选项:"
            echo "  --env              配置文件路径 (必需)"
            echo "  --offline-dir      离线安装包目录（Docker/Compose 二进制文件）"
            echo "  --skip-docker      跳过 Docker 安装检查"
            echo "  --skip-keepalived  跳过 Keepalived 配置"
            echo "  --skip-load        跳过镜像加载"
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

NODE_ROLE="${NODE_ROLE:-master}"
NODE_IP="${NODE_IP:-}"
PEER_IP="${PEER_IP:-}"
VIP="${VIP:-}"

info "=========================================="
info "  tidbx-ha-toolkit 一键部署"
info "  角色: ${NODE_ROLE}"
info "  本机 IP: ${NODE_IP}"
info "  对端 IP: ${PEER_IP}"
info "  VIP: ${VIP}"
info "=========================================="

if [ "$SKIP_DOCKER" = false ]; then
    info "[1/6] 检查 Docker 环境..."
    if ! command -v docker &>/dev/null; then
        warn "Docker 未安装，执行安装..."
        if [ -n "$OFFLINE_DIR" ]; then
            bash "${PROJECT_DIR}/setup/install-docker.sh" --offline-dir "$OFFLINE_DIR"
        else
            bash "${PROJECT_DIR}/setup/install-docker.sh"
        fi
    fi
    if ! docker compose version &>/dev/null; then
        warn "Docker Compose 未安装，执行安装..."
        if [ -n "$OFFLINE_DIR" ]; then
            bash "${PROJECT_DIR}/setup/install-compose.sh" --offline-dir "$OFFLINE_DIR"
        else
            bash "${PROJECT_DIR}/setup/install-compose.sh"
        fi
    fi
    info "Docker 环境就绪 ✅"
else
    info "[1/6] 跳过 Docker 检查"
fi

if [ "$SKIP_LOAD" = false ]; then
    info "[2/6] 加载 Docker 镜像..."
    bash "${SCRIPT_DIR}/load-image.sh" --env "$ENV_FILE"
else
    info "[2/6] 跳过镜像加载"
fi

info "[3/6] 初始化数据目录和配置..."
bash "${SCRIPT_DIR}/init-data.sh" --env "$ENV_FILE"

if [ "$SKIP_KEEPALIVED" = false ]; then
    info "[4/6] 配置 Keepalived..."
    bash "${SCRIPT_DIR}/deploy-keepalived.sh" --env "$ENV_FILE"
else
    info "[4/6] 跳过 Keepalived 配置"
fi

info "[5/6] 启动 Docker Compose..."
if [ "$NODE_ROLE" = "master" ]; then
    COMPOSE_FILE="${PROJECT_DIR}/docker-compose_node1.generated.yml"
else
    COMPOSE_FILE="${PROJECT_DIR}/docker-compose_node2.generated.yml"
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    error "Docker Compose 文件不存在: ${COMPOSE_FILE}"
    exit 1
fi

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
info "Docker Compose 已启动 ✅"

info "[6/6] 等待集群就绪..."
sleep 10

bash "${SCRIPT_DIR}/verify.sh" --env "$ENV_FILE"

info "=========================================="
info "  部署完成！"
info "  集群状态请运行: verify.sh --env ${ENV_FILE}"
info "=========================================="
