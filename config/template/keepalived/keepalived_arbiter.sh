#!/bin/bash
set -euo pipefail

STATE_FILE="/tmp/keepalived_state/tidb_cluster_state"

mkdir -p /tmp/keepalived_state

check_tidb_cluster() {
    local pd_url="http://127.0.0.1:${PD_CLI_PORT:-2379}"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${pd_url}/health" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
        return 0
    fi
    return 1
}

check_mysql() {
    local host="${1:-127.0.0.1}"
    local port="${2:-4000}"

    if command -v mysql &>/dev/null; then
        mysql -h "$host" -P "$port" -u root -e "SELECT 1" &>/dev/null
        return $?
    fi

    return 0
}

check_vip() {
    local vip="${VIP:-}"
    if [ -z "$vip" ]; then
        return 1
    fi
    ip addr show | grep -q "$vip"
    return $?
}

write_state() {
    echo "$1" > "$STATE_FILE"
}

current_state=""
if [ -f "$STATE_FILE" ]; then
    current_state=$(cat "$STATE_FILE" 2>/dev/null || echo "")
fi

if check_tidb_cluster && check_mysql && check_vip; then
    if [ "$current_state" != "OK" ]; then
        write_state "OK"
        logger -t keepalived_arbiter "Cluster state: OK (PD healthy, TiDB available, VIP present)"
    fi
    exit 0
elif check_tidb_cluster; then
    if [ "$current_state" != "DEGRADED" ]; then
        write_state "DEGRADED"
        logger -t keepalived_arbiter "Cluster state: DEGRADED (PD healthy but MySQL or VIP issue)"
    fi
    exit 0
else
    if [ "$current_state" != "FAILED" ]; then
        write_state "FAILED"
        logger -t keepalived_arbiter "Cluster state: FAILED (PD unhealthy)"
    fi
    exit 1
fi
