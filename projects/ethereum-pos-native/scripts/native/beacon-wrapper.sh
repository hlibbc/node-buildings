#!/usr/bin/env bash
# beacon-wrapper.sh — systemd용 Prysm beacon-chain 시작 wrapper
#
# systemd의 EnvironmentFile에서 주입된 env 변수를 읽어 beacon-chain을 실행합니다.
# STATIC_ENRS: 비어 있으면 --bootstrap-node 미추가
# P2P_ADVERTISE_IP: 비어 있으면 --p2p-host-ip 미추가 (ENR에 loopback이 들어갈 수 있음)
# P2P_ADVERTISE_DNS: 비어 있으면 --p2p-host-dns 미추가
#
# 2-node instance 구성에서는 P2P_ADVERTISE_IP 또는 P2P_ADVERTISE_DNS를 설정하지 않으면
# beacon ENR이 loopback 주소를 광고하여 peer 연결에 실패할 수 있습니다.
#
# 설치 위치: /usr/local/bin/beacon-pos-wrapper  (04-install-systemd-services.sh가 설치)
# ExecStart에서 직접 호출됩니다.
set -euo pipefail

: "${BEACON_ROOT:?'BEACON_ROOT 미설정 — EnvironmentFile 확인'}"
: "${CONFIG_ROOT:?'CONFIG_ROOT 미설정'}"
: "${CHAIN_ID:?'CHAIN_ID 미설정'}"
: "${GETH_AUTHRPC_ADDR:?'GETH_AUTHRPC_ADDR 미설정'}"
: "${GETH_AUTHRPC_PORT:?'GETH_AUTHRPC_PORT 미설정'}"
: "${BEACON_GRPC_PORT:?'BEACON_GRPC_PORT 미설정'}"
: "${BEACON_REST_ADDR:?'BEACON_REST_ADDR 미설정'}"
: "${BEACON_REST_PORT:?'BEACON_REST_PORT 미설정'}"
: "${BEACON_P2P_TCP_PORT:?'BEACON_P2P_TCP_PORT 미설정'}"
: "${BEACON_P2P_UDP_PORT:?'BEACON_P2P_UDP_PORT 미설정'}"
: "${FEE_RECIPIENT:?'FEE_RECIPIENT 미설정'}"

EXTRA_ARGS=()

# STATIC_ENRS: bootstrap peer (비어있으면 미추가)
if [ -n "${STATIC_ENRS:-}" ]; then
    EXTRA_ARGS+=(--bootstrap-node="${STATIC_ENRS}")
fi

# P2P 외부 광고 주소 — beacon ENR에 광고할 외부 접근 가능 IP 또는 DNS
# 설정하지 않으면 Prysm이 자동 감지하는데, loopback이나 내부 IP가 들어갈 수 있음
# 2-node 인스턴스 구성에서는 반드시 설정 권장
if [ -n "${P2P_ADVERTISE_IP:-}" ]; then
    EXTRA_ARGS+=(--p2p-host-ip="${P2P_ADVERTISE_IP}")
elif [ -n "${P2P_ADVERTISE_DNS:-}" ]; then
    EXTRA_ARGS+=(--p2p-host-dns="${P2P_ADVERTISE_DNS}")
fi

exec /usr/local/bin/beacon-chain \
    --datadir="${BEACON_ROOT}" \
    --genesis-state="${CONFIG_ROOT}/genesis.ssz" \
    --chain-config-file="${CONFIG_ROOT}/config.yml" \
    --interop-eth1data-votes \
    --contract-deployment-block=0 \
    --chain-id="${CHAIN_ID}" \
    --execution-endpoint="http://${GETH_AUTHRPC_ADDR}:${GETH_AUTHRPC_PORT}" \
    --jwt-secret="${CONFIG_ROOT}/jwtsecret" \
    --accept-terms-of-use \
    --rpc-host=127.0.0.1 \
    --rpc-port="${BEACON_GRPC_PORT}" \
    --grpc-gateway-host="${BEACON_REST_ADDR}" \
    --grpc-gateway-port="${BEACON_REST_PORT}" \
    --p2p-tcp-port="${BEACON_P2P_TCP_PORT}" \
    --p2p-udp-port="${BEACON_P2P_UDP_PORT}" \
    --minimum-peers-per-subnet=0 \
    --min-sync-peers=0 \
    --suggested-fee-recipient="${FEE_RECIPIENT}" \
    "${EXTRA_ARGS[@]}"
