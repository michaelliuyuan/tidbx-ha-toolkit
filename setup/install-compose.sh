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

check_compose_installed() {
    if docker compose version &>/dev/null; then
        local ver
        ver=$(docker compose version 2>/dev/null)
        info "Docker Compose 已安装: ${ver}"
        return 0
    fi
    return 1
}

install_compose_offline_plugin() {
    local pkg_dir="$1"
    info "离线安装 Docker Compose 插件..."

    local plugin_dir="/usr/local/lib/docker/cli-plugins"
    mkdir -p "$plugin_dir"

    local found=false

    for f in "${pkg_dir}"/docker-compose*; do
        if [ -f "$f" ]; then
            cp "$f" "${plugin_dir}/docker-compose"
            chmod +x "${plugin_dir}/docker-compose"
            found=true
            info "从离线包安装: $(basename "$f")"
            break
        fi
    done

    if [ "$found" = false ]; then
        for f in "${pkg_dir}"/*.tar.gz; do
            if [ -f "$f" ]; then
                tar -xzf "$f" -C "$plugin_dir"
                chmod +x "${plugin_dir}/docker-compose" 2>/dev/null || true
                found=true
                info "从离线 tar.gz 安装: $(basename "$f")"
                break
            fi
        done
    fi

    if [ "$found" = false ]; then
        error "未找到 Docker Compose 离线包: ${pkg_dir}"
        error "需要文件: docker-compose-linux-x86_64 或 docker-compose-linux-aarch64"
        exit 1
    fi

    docker compose version
    info "Docker Compose 离线安装完成 ✅"
}

install_compose_online() {
    if ! command -v docker &>/dev/null; then
        error "Docker 未安装，请先运行 install-docker.sh"
        exit 1
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
    fi

    case "${ID:-unknown}" in
        centos|rhel|rocky|almalinux)
            yum install -y docker-compose-plugin
            ;;
        ubuntu|debian)
            apt-get update
            apt-get install -y docker-compose-plugin
            ;;
        *)
            warn "包管理器安装失败，尝试手动下载..."
            local arch
            arch=$(uname -m)
            case "$arch" in
                x86_64)  arch="x86_64" ;;
                aarch64) arch="aarch64" ;;
                *) error "不支持的架构: $arch"; exit 1 ;;
            esac
            local plugin_dir="/usr/local/lib/docker/cli-plugins"
            mkdir -p "$plugin_dir"
            local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}"
            curl -SL "$compose_url" -o "${plugin_dir}/docker-compose"
            chmod +x "${plugin_dir}/docker-compose"
            ;;
    esac

    docker compose version
    info "Docker Compose 安装完成 ✅"
}

main() {
    local offline_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --offline-dir) offline_dir="$2"; shift 2 ;;
            --help|-h)
                echo "用法: $0 [--offline-dir <dir>]"
                echo ""
                echo "选项:"
                echo "  --offline-dir  离线安装包目录（包含 docker-compose 二进制文件）"
                exit 0
                ;;
            *) error "未知参数: $1"; exit 1 ;;
        esac
    done

    if [ "$(id -u)" -ne 0 ]; then
        error "请使用 root 用户或 sudo 执行此脚本"
        exit 1
    fi

    if check_compose_installed; then
        warn "Docker Compose 已安装，跳过"
        exit 0
    fi

    if [ -n "$offline_dir" ]; then
        install_compose_offline_plugin "$offline_dir"
    else
        install_compose_online
    fi
}

main "$@"
