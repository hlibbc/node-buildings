#!/usr/bin/env bash
# geth-wrapper.sh — systemd용 Geth 시작 wrapper
#
# systemd의 EnvironmentFile에서 주입된 env 변수를 읽어 geth를 실행합니다.
# STATIC_BOOTNODES가 비어 있으면 --bootnodes 플래그를 추가하지 않습니다.
#
# 설치 위치: /usr/local/bin/geth-pos-wrapper  (04-install-systemd-services.sh가 설치)
# ExecStart에서 직접 호출됩니다.
set -euo pipefail

: "${EXECUTION_ROOT:?'EXECUTION_ROOT 미설정 — EnvironmentFile 확인'}"
: "${NETWORK_ID:?'NETWORK_ID 미설정'}"
: "${GETH_P2P_PORT:?'GETH_P2P_PORT 미설정'}"
: "${GETH_HTTP_ADDR:?'GETH_HTTP_ADDR 미설정'}"
: "${GETH_HTTP_PORT:?'GETH_HTTP_PORT 미설정'}"
: "${GETH_AUTHRPC_ADDR:?'GETH_AUTHRPC_ADDR 미설정'}"
: "${GETH_AUTHRPC_PORT:?'GETH_AUTHRPC_PORT 미설정'}"
: "${CONFIG_ROOT:?'CONFIG_ROOT 미설정'}"

EXTRA_ARGS=()

# STATIC_BOOTNODES가 설정된 경우에만 --bootnodes 추가
if [ -n "${STATIC_BOOTNODES:-}" ]; then
    EXTRA_ARGS+=(--bootnodes="${STATIC_BOOTNODES}")
fi

# GETH_WS_ENABLED=true 일 때만 WebSocket 옵션 추가
if [ "${GETH_WS_ENABLED:-false}" = "true" ]; then
    EXTRA_ARGS+=(
        --ws
        --ws.api=eth,net,web3
        --ws.addr="${GETH_WS_ADDR:-0.0.0.0}"
        --ws.port="${GETH_WS_PORT:-8546}"
        --ws.origins='*'
    )
fi

# /usr/local/bin/geth: apt 설치 시 /usr/bin/geth → /usr/local/bin/geth symlink
exec /usr/local/bin/geth \
    --datadir="${EXECUTION_ROOT}" \
    --syncmode=full \
    --networkid="${NETWORK_ID}" \
    --port="${GETH_P2P_PORT}" \
    --http \
    --http.api=eth,net,web3,txpool \
    --http.addr="${GETH_HTTP_ADDR}" \
    --http.port="${GETH_HTTP_PORT}" \
    --http.corsdomain='*' \
    --http.vhosts='*' \
    --authrpc.addr="${GETH_AUTHRPC_ADDR}" \
    --authrpc.port="${GETH_AUTHRPC_PORT}" \
    --authrpc.jwtsecret="${CONFIG_ROOT}/jwtsecret" \
    --authrpc.vhosts='localhost,127.0.0.1' \
    "${EXTRA_ARGS[@]}"
