#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

IMAGE_FILE=""
IMAGE_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image-file) IMAGE_FILE="$2"; shift 2 ;;
        --image-name) IMAGE_NAME="$2"; shift 2 ;;
        --env) source "$2"; shift 2 ;;
        --help|-h)
            echo "用法: $0 --env <config.env> [--image-file <file>] [--image-name <name>]"
            exit 0 ;;
        *) error "未知参数: $1"; exit 1 ;;
    esac
done

IMAGE_FILE="${IMAGE_FILE:-${TIDBX_IMAGE_FILE:-}}"
IMAGE_NAME="${IMAGE_NAME:-${TIDBX_IMAGE:-}}"

if [ -z "$IMAGE_FILE" ] || [ -z "$IMAGE_NAME" ]; then
    error "请指定 --image-file 和 --image-name 或通过 .env 配置"
    exit 1
fi

if docker image inspect "$IMAGE_NAME" &>/dev/null; then
    info "镜像 ${IMAGE_NAME} 已存在，跳过加载"
    exit 0
fi

if [ ! -f "$IMAGE_FILE" ]; then
    error "镜像文件不存在: ${IMAGE_FILE}"
    exit 1
fi

info "加载 Docker 镜像: ${IMAGE_FILE} ..."
docker load -i "$IMAGE_FILE"

if docker image inspect "$IMAGE_NAME" &>/dev/null; then
    info "镜像加载成功: ${IMAGE_NAME} ✅"
else
    error "镜像加载失败"
    exit 1
fi
