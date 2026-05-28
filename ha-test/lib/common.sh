#!/bin/bash

HA_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$HA_TEST_DIR")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $(date '+%H:%M:%S') $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*"; }
section() { echo -e "${BLUE}[TEST]${NC} $(date '+%H:%M:%S') $*"; }

TEST_RESULTS_DIR="${HA_TEST_DIR}/results"
TEST_REPORT="${TEST_RESULTS_DIR}/report_$(date +%Y%m%d_%H%M%S).txt"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

init_test_env() {
    local env_file="${1:-}"
    if [ -z "$env_file" ]; then
        error "请指定 --env <config.env>"
        exit 1
    fi
    source "$env_file"
    mkdir -p "$TEST_RESULTS_DIR"

    NODE_IP="${NODE_IP:-}"
    PEER_IP="${PEER_IP:-}"
    VIP="${VIP:-}"
    NIC="${NIC:-ens33}"
    PD_CLI_PORT="${PD_CLI_PORT:-2379}"
    TIDB_PORT="${TIDB_PORT:-4000}"
    SSH_USER="${SSH_USER:-root}"
    SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
    if [ "$SSH_USER" != "root" ]; then
        SSH_OPTS="${SSH_OPTS} -o LogLevel=ERROR"
    fi
    SUDO="sudo"
    if [ "$SSH_USER" = "root" ]; then
        SUDO=""
    fi

    export NODE_IP PEER_IP VIP NIC PD_CLI_PORT TIDB_PORT SSH_USER SSH_OPTS SUDO
    export TEST_REPORT TEST_RESULTS_DIR
}

record_result() {
    local test_name="$1"
    local result="$2"
    local detail="${3:-}"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ "$result" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}[PASS]${NC} ${test_name}" | tee -a "$TEST_REPORT"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}[FAIL]${NC} ${test_name}" | tee -a "$TEST_REPORT"
    fi

    if [ -n "$detail" ]; then
        echo "       ${detail}" | tee -a "$TEST_REPORT"
    fi

    echo "[${ts}] ${result} ${test_name} ${detail}" >> "${TEST_RESULTS_DIR}/details.log"
}

get_replication_mode() {
    local ip="${1:-$NODE_IP}"
    local result
    result=$(curl -sf "http://${ip}:${PD_CLI_PORT}/pd/api/v1/replication_mode/status" 2>/dev/null || echo "{}")
    local state
    state=$(echo "$result" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$state" ]; then
        echo "$state"
        return
    fi
    local peer="${PEER_IP:-}"
    if [ -n "$peer" ] && [ "$ip" = "$NODE_IP" ]; then
        result=$(curl -sf "http://${peer}:${PD_CLI_PORT}/pd/api/v1/replication_mode/status" 2>/dev/null || echo "{}")
        state=$(echo "$result" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    echo "${state:-unknown}"
}

wait_for_replication_state() {
    local expected="$1"
    local timeout="${2:-120}"
    local ip="${3:-$NODE_IP}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local mode
        mode=$(get_replication_mode "$ip")
        if [ "$mode" = "$expected" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

check_vip_on_node() {
    local node_ip="$1"
    local vip="${VIP:-}"
    if [ -z "$vip" ]; then
        return 1
    fi
    ssh ${SSH_OPTS} "${SSH_USER}@${node_ip}" "ip addr show | grep -q '${vip}'" 2>/dev/null
}

check_mysql_via_vip() {
    local vip="${VIP:-}"
    local port="${TIDB_PORT:-4000}"
    if command -v mysql &>/dev/null; then
        mysql -h "$vip" -P "$port" -u root -e "SELECT 1" &>/dev/null
    else
        nc -z -w3 "$vip" "$port" 2>/dev/null
    fi
}

add_network_delay() {
    local target_ip="$1"
    local delay="$2"
    local nic="${NIC:-ens33}"
    ssh ${SSH_OPTS} "${SSH_USER}@${target_ip}" \
        "${SUDO} tc qdisc add dev ${nic} root netem delay ${delay}" 2>/dev/null
}

remove_network_delay() {
    local target_ip="$1"
    local nic="${NIC:-ens33}"
    ssh ${SSH_OPTS} "${SSH_USER}@${target_ip}" \
        "${SUDO} tc qdisc del dev ${nic} root 2>/dev/null || true" 2>/dev/null
}

stop_node() {
    local node_ip="$1"
    info "停止节点 ${node_ip} ..."
    ssh ${SSH_OPTS} "${SSH_USER}@${node_ip}" \
        "${SUDO} docker stop \$(${SUDO} docker ps -q) 2>/dev/null; ${SUDO} systemctl stop keepalived" 2>/dev/null
}

start_node() {
    local node_ip="$1"
    info "启动节点 ${node_ip} ..."
    ssh ${SSH_OPTS} "${SSH_USER}@${node_ip}" \
        "${SUDO} systemctl start keepalived; ${SUDO} docker start \$(${SUDO} docker ps -aq) 2>/dev/null" 2>/dev/null
}

ssh_exec() {
    local node_ip="$1"
    shift
    ssh ${SSH_OPTS} "${SSH_USER}@${node_ip}" "$@"
}

generate_report() {
    local report_file="$TEST_REPORT"
    {
        echo ""
        echo "========================================"
        echo "  HA 测试报告"
        echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
        echo ""
        echo "总测试数: ${TOTAL_TESTS}"
        echo "通过: ${PASSED_TESTS}"
        echo "失败: ${FAILED_TESTS}"
        echo ""
        if [ "$FAILED_TESTS" -eq 0 ]; then
            echo "结论: 全部通过 ✅"
        else
            echo "结论: 存在失败 ❌"
        fi
        echo "========================================"
    } | tee -a "$report_file"

    info "测试报告已保存: ${report_file}"
}
