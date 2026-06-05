#!/usr/bin/env bash
# 04-status.sh — 서비스 상태 및 기본 RPC 확인
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음"; exit 1; }
set -a; source "$ENV_FILE"; set +a

NODE0_RPC="http://localhost:${NODE0_RPC_PORT:-8545}"
NODE1_RPC="http://localhost:${NODE1_RPC_PORT:-8645}"
NODE0_BEACON="http://localhost:${NODE0_BEACON_PORT:-3500}"
NODE1_BEACON="http://localhost:${NODE1_BEACON_PORT:-3600}"

echo "=== 서비스 상태 ==="
docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    --env-file "$ENV_FILE" \
    ps

echo ""
echo "--- Geth RPC ---"
for NODE_RPC in "$NODE0_RPC" "$NODE1_RPC"; do
    LABEL="node0"
    [ "$NODE_RPC" = "$NODE1_RPC" ] && LABEL="node1"
    BLOCK=$(curl -sf -X POST "$NODE_RPC" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // "연결 실패"' 2>/dev/null || echo "연결 실패")
    PEERS=$(curl -sf -X POST "$NODE_RPC" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // "?"' 2>/dev/null || echo "?")
    echo "  [$LABEL] blockNumber=$BLOCK  peerCount=$PEERS  ($NODE_RPC)"
done

echo ""
echo "--- Beacon REST ---"
for NODE_BEACON in "$NODE0_BEACON" "$NODE1_BEACON"; do
    LABEL="node0"
    [ "$NODE_BEACON" = "$NODE1_BEACON" ] && LABEL="node1"
    HEALTH=$(curl -sf "${NODE_BEACON}/eth/v1/node/health" \
        -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    SYNC=$(curl -sf "${NODE_BEACON}/eth/v1/node/syncing" 2>/dev/null || echo "")
    SLOT=$(echo "$SYNC" | jq -r '.data.head_slot // "?"' 2>/dev/null || echo "?")
    SYNC_DIST=$(echo "$SYNC" | jq -r '.data.sync_distance // "?"' 2>/dev/null || echo "?")
    EL_OFFLINE=$(echo "$SYNC" | jq -r '.data.el_offline // "?"' 2>/dev/null || echo "?")
    PEERS=$(curl -sf "${NODE_BEACON}/eth/v1/node/peers" 2>/dev/null \
        | jq '.data | length' 2>/dev/null || echo "?")
    FIN=$(curl -sf "${NODE_BEACON}/eth/v1/beacon/states/head/finality_checkpoints" 2>/dev/null \
        | jq -r '.data.finalized.epoch // "?"' 2>/dev/null || echo "?")
    echo "  [$LABEL] health=HTTP${HEALTH}  head_slot=${SLOT}  sync_distance=${SYNC_DIST}  el_offline=${EL_OFFLINE}  peers=${PEERS}  finalized_epoch=${FIN}"
done
