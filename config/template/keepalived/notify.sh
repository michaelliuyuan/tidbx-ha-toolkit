#!/bin/bash
set -euo pipefail

STATE="$1"
ROLE="$2"
VIP="${VIP:-}"
NIC="${NIC:-ens33}"

case "$STATE" in
    MASTER)
        logger -t keepalived_notify "Transitioning to MASTER on ${NIC}"
        if [ -n "$VIP" ]; then
            ip addr add "${VIP}/${VIP_PREFIX:-24}" dev "${NIC}" 2>/dev/null || true
        fi
        arping -c 3 -A -I "${NIC}" "${VIP}" 2>/dev/null || true
        logger -t keepalived_notify "VIP ${VIP} activated"
        ;;
    BACKUP)
        logger -t keepalived_notify "Transitioning to BACKUP"
        if [ -n "$VIP" ]; then
            ip addr del "${VIP}/${VIP_PREFIX:-24}" dev "${NIC}" 2>/dev/null || true
        fi
        ;;
    FAULT)
        logger -t keepalived_notify "Entering FAULT state"
        if [ -n "$VIP" ]; then
            ip addr del "${VIP}/${VIP_PREFIX:-24}" dev "${NIC}" 2>/dev/null || true
        fi
        ;;
    *)
        logger -t keepalived_notify "Unknown state: $STATE"
        ;;
esac

exit 0
