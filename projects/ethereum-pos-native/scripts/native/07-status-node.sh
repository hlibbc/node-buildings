#!/usr/bin/env bash
# 07-status-node.sh — 노드 상태 확인
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"

# --- env 로드 ---
ENV_FILE="$PROJECT_DIR/.env"
for _arg in "$@"; do
    case "$_arg" in --env=*) ENV_FILE="${_arg#*=}"; break ;; esac
done
[ -f "$ENV_FILE" ] || { echo "ERROR: env 파일 없음: $ENV_FILE"; exit 1; }
set -a; source "$ENV_FILE"; set +a
echo "ENV: $ENV_FILE  (NODE_NAME=${NODE_NAME})"

NODE_NAME="${NODE_NAME:?'ERROR: NODE_NAME 미설정'}"
GETH_SVC="eth-pos-geth-${NODE_NAME}"
BEACON_SVC="eth-pos-beacon-${NODE_NAME}"
VALIDATOR_SVC="eth-pos-validator-${NODE_NAME}"
GETH_HTTP_PORT="${GETH_HTTP_PORT:-8545}"
BEACON_REST_PORT="${BEACON_REST_PORT:-3500}"

echo ""
echo "=== ${NODE_NAME} 상태 ==="

echo ""
echo "--- systemd 서비스 ---"
for _svc in "$GETH_SVC" "$BEACON_SVC" "$VALIDATOR_SVC"; do
    STATUS=$(systemctl is-active "$_svc" 2>/dev/null || echo "not-found")
    ENABLED=$(systemctl is-enabled "$_svc" 2>/dev/null || echo "not-found")
    echo "  [$STATUS / $ENABLED] $_svc"
done

echo ""
echo "--- Geth RPC ---"
GETH_URL="http://127.0.0.1:${GETH_HTTP_PORT}"
if command -v curl &>/dev/null; then
    BLOCK_NUM=$(curl -sf -X POST "$GETH_URL" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // "ERROR"' 2>/dev/null || echo "연결 실패")
    CHAIN_ID_HEX=$(curl -sf -X POST "$GETH_URL" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // "ERROR"' 2>/dev/null || echo "연결 실패")
    PEER_COUNT=$(curl -sf -X POST "$GETH_URL" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // "ERROR"' 2>/dev/null || echo "연결 실패")
    echo "  chainId:    $CHAIN_ID_HEX"
    echo "  blockNumber: $BLOCK_NUM"
    echo "  peerCount:  $PEER_COUNT"
else
    echo "  curl 없음 — RPC 확인 불가"
fi

echo ""
echo "--- Beacon REST API ---"
BEACON_URL="http://127.0.0.1:${BEACON_REST_PORT}"
if command -v curl &>/dev/null; then
    HEALTH=$(curl -sf "${BEACON_URL}/eth/v1/node/health" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "연결 실패")
    SYNC_JSON=$(curl -sf "${BEACON_URL}/eth/v1/node/syncing" 2>/dev/null | jq -c '.data // "ERROR"' 2>/dev/null || echo "연결 실패")
    echo "  health:  HTTP $HEALTH"
    echo "  syncing: $SYNC_JSON"
else
    echo "  curl 없음 — Beacon REST 확인 불가"
fi

echo ""
echo "--- 최근 로그 (각 5줄) ---"
for _svc in "$GETH_SVC" "$BEACON_SVC" "$VALIDATOR_SVC"; do
    STATUS=$(systemctl is-active "$_svc" 2>/dev/null || echo "inactive")
    if [ "$STATUS" = "active" ]; then
        echo "  [$_svc]"
        journalctl -u "$_svc" --no-pager -n 5 2>/dev/null | sed 's/^/    /' || true
    fi
done

echo ""
echo "상세 로그 확인:"
echo "  journalctl -u $GETH_SVC -f"
echo "  journalctl -u $BEACON_SVC -f"
echo "  finality 검증: npm run verify"
