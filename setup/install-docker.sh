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

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
        OS_VERSION="7"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
    export OS_ID OS_VERSION
}

check_docker_installed() {
    if command -v docker &>/dev/null; then
        local ver
        ver=$(docker --version 2>/dev/null || echo "unknown")
        info "Docker 已安装: ${ver}"
        return 0
    fi
    return 1
}

install_docker_offline_centos() {
    local pkg_dir="$1"
    info "离线安装 Docker (CentOS/RHEL)..."
    local rpms=()
    for f in "${pkg_dir}"/*.rpm; do
        [ -f "$f" ] && rpms+=("$f")
    done
    if [ ${#rpms[@]} -eq 0 ]; then
        error "未找到 .rpm 安装包: ${pkg_dir}"
        exit 1
    fi
    yum localinstall -y "${rpms[@]}"
    systemctl enable docker
    systemctl start docker
    info "Docker 离线安装完成"
}

install_docker_offline_ubuntu() {
    local pkg_dir="$1"
    info "离线安装 Docker (Ubuntu/Debian)..."
    local debs=()
    for f in "${pkg_dir}"/*.deb; do
        [ -f "$f" ] && debs+=("$f")
    done
    if [ ${#debs[@]} -eq 0 ]; then
        error "未找到 .deb 安装包: ${pkg_dir}"
        exit 1
    fi
    dpkg -i "${debs[@]}" || apt-get install -f -y
    systemctl enable docker
    systemctl start docker
    info "Docker 离线安装完成"
}

install_docker_offline_binary() {
    local pkg_dir="$1"
    info "离线安装 Docker (二进制方式)..."
    local tar_file=""
    for f in "${pkg_dir}"/docker-*.tgz "${pkg_dir}"/docker-*.tar.gz; do
        [ -f "$f" ] && tar_file="$f" && break
    done
    if [ -z "$tar_file" ]; then
        error "未找到 Docker 二进制包 (docker-*.tgz): ${pkg_dir}"
        exit 1
    fi
    tar -xzvf "$tar_file" -C /usr/local/bin --strip-components=1
    if [ ! -f /etc/systemd/system/docker.service ]; then
        cat > /etc/systemd/system/docker.service <<'EOF'
[Unit]
Description=Docker Application Container Engine
After=network-online.target docker.socket
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/dockerd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker
    info "Docker 二进制离线安装完成"
}

install_docker_centos() {
    info "在线安装 Docker CE (CentOS/RHEL)..."
    yum install -y yum-utils
    yum-config-manager -y --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum makecache
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    info "Docker CE 安装完成"
}

install_docker_ubuntu() {
    info "在线安装 Docker CE (Ubuntu/Debian)..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    info "Docker CE 安装完成"
}

configure_docker() {
    mkdir -p /etc/docker
    if [ ! -f /etc/docker/daemon.json ]; then
        cat > /etc/docker/daemon.json <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}
EOF
    fi
    systemctl daemon-reload
}

main() {
    local offline_dir=""
    local mirror=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --offline-dir) offline_dir="$2"; shift 2 ;;
            --mirror) mirror="$2"; shift 2 ;;
            --help|-h)
                echo "用法: $0 [--offline-dir <dir>] [--mirror <url>]"
                echo ""
                echo "选项:"
                echo "  --offline-dir  离线安装包目录（包含 .rpm/.deb/.tgz 文件）"
                echo "  --mirror       配置 Docker 镜像加速器 URL（仅在线模式）"
                exit 0
                ;;
            *) error "未知参数: $1"; exit 1 ;;
        esac
    done

    if [ "$(id -u)" -ne 0 ]; then
        error "请使用 root 用户或 sudo 执行此脚本"
        exit 1
    fi

    detect_os
    info "操作系统: ${OS_ID} ${OS_VERSION}"

    if check_docker_installed; then
        warn "Docker 已安装，跳过安装步骤"
    else
        if [ -n "$offline_dir" ]; then
            info "使用离线安装模式: ${offline_dir}"
            case "${OS_ID}" in
                centos|rhel|rocky|almalinux)
                    if ls "${offline_dir}"/*.rpm &>/dev/null; then
                        install_docker_offline_centos "$offline_dir"
                    else
                        install_docker_offline_binary "$offline_dir"
                    fi
                    ;;
                ubuntu|debian)
                    if ls "${offline_dir}"/*.deb &>/dev/null; then
                        install_docker_offline_ubuntu "$offline_dir"
                    else
                        install_docker_offline_binary "$offline_dir"
                    fi
                    ;;
                *)
                    install_docker_offline_binary "$offline_dir"
                    ;;
            esac
        else
            case "${OS_ID}" in
                centos|rhel|rocky|almalinux)
                    install_docker_centos
                    ;;
                ubuntu|debian)
                    install_docker_ubuntu
                    ;;
                *)
                    error "不支持的操作系统: ${OS_ID}，请使用 --offline-dir 提供离线安装包"
                    exit 1
                    ;;
            esac
        fi
    fi

    configure_docker

    if [ -n "$mirror" ]; then
        info "配置 Docker 镜像加速: ${mirror}"
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": ["${mirror}"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}
EOF
        systemctl daemon-reload
        systemctl restart docker
    fi

    docker --version
    info "Docker 安装验证完成 ✅"
}

main "$@"
