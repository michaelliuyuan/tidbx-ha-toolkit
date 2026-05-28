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
    state=$(echo "$result" | grep -oE '"state"\s*:\s*"[^"]*"' | head -1 | grep -oE '"[A-Za-z]+"$' | tr -d '"' || true)
    if [ -n "$state" ]; then
        echo "$state"
        return
    fi
    local peer="${PEER_IP:-}"
    if [ -n "$peer" ] && [ "$ip" = "$NODE_IP" ]; then
        result=$(curl -sf "http://${peer}:${PD_CLI_PORT}/pd/api/v1/replication_mode/status" 2>/dev/null || echo "{}")
        state=$(echo "$result" | grep -oE '"state"\s*:\s*"[^"]*"' | head -1 | grep -oE '"[A-Za-z]+"$' | tr -d '"' || true)
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

wait_for_async_with_retry() {
    local expected="$1"
    local ip="${2:-$NODE_IP}"
    local max_retries="${3:-10}"
    local interval="${4:-10}"
    local attempt=0

    while [ $attempt -lt $max_retries ]; do
        local mode
        mode=$(get_replication_mode "$ip")
        if [ "$mode" = "$expected" ]; then
            echo "$mode"
            return 0
        fi
        sleep "$interval"
        attempt=$((attempt + 1))
    done
    echo "unknown"
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

BUSINESS_LOAD_DIR="/tmp/tidbx_business_load"
PHASE_MARKER_FILE="${BUSINESS_LOAD_DIR}/phase_markers.csv"
BUSINESS_CONCURRENCY=10

start_concurrent_load() {
    local vip="${VIP:-}"
    local port="${TIDB_PORT:-4000}"
    local duration="${1:-600}"
    local concurrency="${2:-${BUSINESS_CONCURRENCY}}"

    if [ -z "$vip" ]; then
        error "VIP 未设置，无法启动并发业务模拟"
        return 1
    fi

    rm -rf "$BUSINESS_LOAD_DIR"
    mkdir -p "$BUSINESS_LOAD_DIR"
    echo "timestamp,phase,action" > "$PHASE_MARKER_FILE"

    if ! command -v mysql &>/dev/null; then
        warn "mysql 客户端未安装，并发业务模拟无法运行"
        return 1
    fi

    mysql -h "$vip" -P "$port" -u root -e "
        CREATE DATABASE IF NOT EXISTS ha_test;
        USE ha_test;
        CREATE TABLE IF NOT EXISTS concurrent_test (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            worker_id INT NOT NULL,
            seq_num BIGINT NOT NULL,
            val VARCHAR(100),
            ts TIMESTAMP(3)(3) DEFAULT CURRENT_TIMESTAMP(3),
            UNIQUE KEY uk_worker_seq (worker_id, seq_num)
        );
        TRUNCATE TABLE concurrent_test;
    " 2>/dev/null || true

    info "启动 ${concurrency} 并发业务模拟 (VIP=${vip}, 时长=${duration}s)"

    local worker_pids=""
    for i in $(seq 1 "$concurrency"); do
        (
            local worker_id=$i
            local seq=0
            local start_time
            start_time=$(date +%s)
            local log_file="${BUSINESS_LOAD_DIR}/worker_${worker_id}.csv"
            echo "timestamp,success,latency_ms" > "$log_file"

            while true; do
                local now
                now=$(date +%s)
                if [ $((now - start_time)) -ge "$duration" ]; then
                    break
                fi

                seq=$((seq + 1))
                local ts
                ts=$(date '+%Y-%m-%d-%H:%M:%S.%3N')
                local start_ms
                start_ms=$(date +%s%3N 2>/dev/null || echo "0")
                local val="w${worker_id}_s${seq}"

                if mysql -h "$vip" -P "$port" -u root -e "
                    USE ha_test;
                    INSERT INTO concurrent_test (worker_id, seq_num, val) VALUES (${worker_id}, ${seq}, '${val}');
                " &>/dev/null; then
                    local end_ms
                    end_ms=$(date +%s%3N 2>/dev/null || echo "0")
                    local latency=$((end_ms - start_ms))
                    echo "${ts},1,${latency}" >> "$log_file"
                else
                    echo "${ts},0,0" >> "$log_file"
                fi

                sleep 0.1
            done
        ) &
        worker_pids="${worker_pids} $!"
    done

    echo "$worker_pids" | tr ' ' '\n' | grep -v '^$' > "${BUSINESS_LOAD_DIR}/workers.pid"
    sleep 1
    info "并发业务模拟已启动，${concurrency} 个 worker 运行中"
}

stop_concurrent_load() {
    if [ -f "${BUSINESS_LOAD_DIR}/workers.pid" ]; then
        while read -r pid; do
            [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        done < "${BUSINESS_LOAD_DIR}/workers.pid"
        sleep 1
        while read -r pid; do
            [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
        done < "${BUSINESS_LOAD_DIR}/workers.pid"
        rm -f "${BUSINESS_LOAD_DIR}/workers.pid"
    fi
    info "并发业务模拟已停止"
}

mark_phase() {
    local phase_name="$1"
    local action="$2"
    local ts
    ts=$(date '+%Y-%m-%d-%H:%M:%S.%3N')
    echo "${ts},${phase_name},${action}" >> "$PHASE_MARKER_FILE"
}

check_data_consistency() {
    local vip="${VIP:-}"
    local port="${TIDB_PORT:-4000}"
    local result_file="${BUSINESS_LOAD_DIR}/consistency_check.log"

    if ! command -v mysql &>/dev/null; then
        echo "mysql 客户端未安装，跳过一致性检查" > "$result_file"
        echo "$result_file"
        return
    fi

    {
        mysql -h "$vip" -P "$port" -u root -e "
            USE ha_test;
            SELECT 'total_rows' AS metric, COUNT(*) AS value FROM concurrent_test;
            SELECT worker_id,
                   MIN(seq_num) AS min_seq,
                   MAX(seq_num) AS max_seq,
                   COUNT(*) AS actual_count,
                   MAX(seq_num) - MIN(seq_num) + 1 AS expected_count,
                   CASE WHEN COUNT(*) = MAX(seq_num) - MIN(seq_num) + 1 THEN 'OK' ELSE 'GAP' END AS status
            FROM concurrent_test
            GROUP BY worker_id
            ORDER BY worker_id;
        " 2>/dev/null
    } > "$result_file"

    echo "$result_file"
}

compute_impact_stats() {
    local output_file="${BUSINESS_LOAD_DIR}/impact_stats.log"
    local marker_file="$PHASE_MARKER_FILE"

    if [ ! -f "$marker_file" ]; then
        echo "无 phase 标记文件" > "$output_file"
        echo "$output_file"
        return
    fi

    {
        echo "==========================================="
        echo "  每个测试场景的业务影响统计"
        echo "==========================================="

        local phases
        phases=$(tail -n +2 "$marker_file" | cut -d',' -f2 | sort -u)

        for phase in $phases; do
            local start_ts end_ts
            start_ts=$(grep ",${phase},start" "$marker_file" | tail -1 | cut -d',' -f1)
            end_ts=$(grep ",${phase},end" "$marker_file" | tail -1 | cut -d',' -f1)

            if [ -z "$start_ts" ] || [ -z "$end_ts" ]; then
                echo ""
                echo "--- ${phase} ---"
                echo "  缺少标记，跳过"
                continue
            fi

            echo ""
            echo "--- ${phase} ---"
            echo "  开始: ${start_ts}"
            echo "  结束: ${end_ts}"

            local total_ops=0 fail_ops=0 success_ops=0 total_latency=0 latency_count=0

            for wf in "${BUSINESS_LOAD_DIR}"/worker_*.csv; do
                [ -f "$wf" ] || continue
                while IFS=',' read -r ts success latency; do
                    [ "$ts" = "timestamp" ] && continue
                    [ -z "$ts" ] && continue

                    if [[ "$ts" > "$start_ts" || "$ts" = "$start_ts" ]] && [[ "$ts" < "$end_ts" || "$ts" = "$end_ts" ]]; then
                        total_ops=$((total_ops + 1))
                        if [ "$success" = "1" ]; then
                            success_ops=$((success_ops + 1))
                            latency_count=$((latency_count + 1))
                            total_latency=$((total_latency + latency))
                        else
                            fail_ops=$((fail_ops + 1))
                        fi
                    fi
                done < "$wf"
            done

            if [ $total_ops -gt 0 ]; then
                local fail_rate
                if [ $total_ops -gt 0 ]; then
                    fail_rate=$(awk "BEGIN{printf \"%.2f\",${fail_ops}*100/${total_ops}}")
                else
                    fail_rate="0.00"
                fi
                local avg_latency=0
                if [ $latency_count -gt 0 ]; then
                    avg_latency=$((total_latency / latency_count))
                fi
                echo "  总操作数: ${total_ops}"
                echo "  成功: ${success_ops}, 失败: ${fail_ops}"
                echo "  失败率: ${fail_rate}%"
                echo "  平均延迟: ${avg_latency}ms"
            else
                echo "  无业务操作记录"
            fi
        done
    } > "$output_file"

    echo "$output_file"
}

check_concurrent_load_running() {
    if [ ! -f "${BUSINESS_LOAD_DIR}/workers.pid" ]; then
        return 1
    fi
    local alive=0
    while read -r pid; do
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=$((alive + 1))
    done < "${BUSINESS_LOAD_DIR}/workers.pid"
    [ $alive -gt 0 ]
}

snapshot_concurrent_stats() {
    local label="$1"
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
    info "[业务快照:${label}] 总操作=${total_ops}, 成功=${success_ops}, 失败=${fail_ops}"
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
