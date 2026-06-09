#!/usr/bin/env bash
# 09-export-artifact.sh — L1 chain-info artifact 생성
#
# 생성 파일: ./artifacts/l1-chain-info.json
# 전제 조건: el_offline=false, beacon peers>=1, finalized epoch>0
#
# 사용: pnpm run export:artifact
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
PREFUND_FILE="$PROJECT_DIR/config/prefund.json"  # legacy; artifact now uses L2_*_ADDRESS env vars
ARTIFACTS_DIR="$PROJECT_DIR/artifacts"
OUTPUT_FILE="$ARTIFACTS_DIR/l1-chain-info.json"

# --- env 로드 ---
[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음 — cp .env.sample .env"; exit 1; }
set -a; source "$ENV_FILE"; set +a

NODE0_RPC="http://localhost:${NODE0_RPC_PORT:-8545}"
NODE1_RPC="http://localhost:${NODE1_RPC_PORT:-8645}"
NODE0_WS="ws://localhost:${NODE0_WS_PORT:-8546}"
NODE1_WS="ws://localhost:${NODE1_WS_PORT:-8646}"
NODE0_BEACON="http://localhost:${NODE0_BEACON_PORT:-3500}"
NODE1_BEACON="http://localhost:${NODE1_BEACON_PORT:-3600}"

DEPOSIT_ADDR="${DEPOSIT_CONTRACT_ADDRESS:-0x4242424242424242424242424242424242424242}"
FEE_ADDR="${FEE_RECIPIENT:-0x0000000000000000000000000000000000000000}"

echo "=== L1 chain-info artifact 생성 ==="
echo ""

# --- 사전 조건 확인 ---
echo "--- 사전 조건 확인 ---"
FAIL=0

for INFO in "node0|$NODE0_BEACON" "node1|$NODE1_BEACON"; do
    LABEL="${INFO%%|*}"
    BURL="${INFO#*|}"

    SYNC=$(curl -sf "${BURL}/eth/v1/node/syncing" 2>/dev/null || echo "")
    EL=$(echo "$SYNC" | jq -r 'if .data.el_offline == null then "true" else (.data.el_offline | tostring) end' 2>/dev/null || echo "true")
    PEERS=$(curl -sf "${BURL}/eth/v1/node/peers" 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo "0")
    FIN=$(curl -sf "${BURL}/eth/v1/beacon/states/head/finality_checkpoints" 2>/dev/null \
        | jq -r '.data.finalized.epoch // "0"' 2>/dev/null || echo "0")

    if [ "$EL" = "false" ]; then
        echo "  [OK]   [$LABEL] el_offline=false"
    else
        echo "  [FAIL] [$LABEL] el_offline=$EL"
        FAIL=1
    fi

    if [ "${PEERS:-0}" -ge 1 ]; then
        echo "  [OK]   [$LABEL] peers=$PEERS"
    else
        echo "  [FAIL] [$LABEL] peers=$PEERS (need >= 1)"
        FAIL=1
    fi

    if [ "${FIN:-0}" -gt 0 ]; then
        echo "  [OK]   [$LABEL] finalized_epoch=$FIN"
    else
        echo "  [FAIL] [$LABEL] finalized_epoch=$FIN (need > 0)"
        FAIL=1
    fi
done

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "ERROR: 사전 조건 미충족 — artifact 생성 중단"
    echo "       pnpm run verify 로 상태 확인 후 재시도하세요"
    exit 1
fi

echo ""
echo "--- 데이터 수집 ---"

# Geth
_rpc() {
    curl -sf -X POST "$1" -H 'Content-Type: application/json' -d "$2" 2>/dev/null
}

B0_NUM=$(_rpc "$NODE0_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result // "0x0"')
B0_PEERS_HEX=$(_rpc "$NODE0_RPC" '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    | jq -r '.result // "0x0"')
B1_NUM=$(_rpc "$NODE1_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result // "0x0"')
B1_PEERS_HEX=$(_rpc "$NODE1_RPC" '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    | jq -r '.result // "0x0"')

B0_PEERS=$(printf '%d' "${B0_PEERS_HEX:-0x0}" 2>/dev/null || echo "0")
B1_PEERS=$(printf '%d' "${B1_PEERS_HEX:-0x0}" 2>/dev/null || echo "0")

# Beacon node0
N0_SYNC=$(curl -sf "${NODE0_BEACON}/eth/v1/node/syncing" 2>/dev/null || echo "{}")
N0_SLOT=$(echo "$N0_SYNC" | jq -r '.data.head_slot // "0"')
N0_DIST=$(echo "$N0_SYNC" | jq -r '.data.sync_distance // "0"')
N0_EL=$(echo "$N0_SYNC" | jq -r 'if .data.el_offline == null then "false" else (.data.el_offline | tostring) end' 2>/dev/null || echo "false")
N0_PEERS=$(curl -sf "${NODE0_BEACON}/eth/v1/node/peers" 2>/dev/null | jq '.data | length // 0' || echo "0")
N0_FIN=$(curl -sf "${NODE0_BEACON}/eth/v1/beacon/states/head/finality_checkpoints" 2>/dev/null || echo "{}")
N0_FIN_EPOCH=$(echo "$N0_FIN" | jq -r '.data.finalized.epoch // "0"')
N0_FIN_ROOT=$(echo "$N0_FIN" | jq -r '.data.finalized.root // "0x0"')

# Beacon node1
N1_SYNC=$(curl -sf "${NODE1_BEACON}/eth/v1/node/syncing" 2>/dev/null || echo "{}")
N1_SLOT=$(echo "$N1_SYNC" | jq -r '.data.head_slot // "0"')
N1_DIST=$(echo "$N1_SYNC" | jq -r '.data.sync_distance // "0"')
N1_EL=$(echo "$N1_SYNC" | jq -r 'if .data.el_offline == null then "false" else (.data.el_offline | tostring) end' 2>/dev/null || echo "false")
N1_PEERS=$(curl -sf "${NODE1_BEACON}/eth/v1/node/peers" 2>/dev/null | jq '.data | length // 0' || echo "0")
N1_FIN=$(curl -sf "${NODE1_BEACON}/eth/v1/beacon/states/head/finality_checkpoints" 2>/dev/null || echo "{}")
N1_FIN_EPOCH=$(echo "$N1_FIN" | jq -r '.data.finalized.epoch // "0"')
N1_FIN_ROOT=$(echo "$N1_FIN" | jq -r '.data.finalized.root // "0x0"')

# Validators
V0=$(curl -sf "${NODE0_BEACON}/eth/v1/beacon/states/head/validators/0" 2>/dev/null \
    | jq -r '.data.status // "unknown"')
V32=$(curl -sf "${NODE1_BEACON}/eth/v1/beacon/states/head/validators/32" 2>/dev/null \
    | jq -r '.data.status // "unknown"')

# --- prefundedAccounts: L2 depositor from .env ---
PREFUND_JSON='[]'
_L2DEP_ADDR="${L2_DEPOSITOR_ADDRESS:-}"

if printf '%s' "$_L2DEP_ADDR" | grep -qE '^0x[0-9a-fA-F]{40}$'; then
    _L2DEP_ADDR_LC=$(printf '%s' "$_L2DEP_ADDR" | tr '[:upper:]' '[:lower:]')
    _l2dep_bal_hex=$(_rpc "$NODE0_RPC" \
        "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"${_L2DEP_ADDR_LC}\",\"latest\"],\"id\":1}" \
        | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
    _l2dep_bal_eth=$(node -e \
        "try{process.stdout.write((BigInt('${_l2dep_bal_hex}')/10n**18n).toString())}catch(e){process.stdout.write('?')}" \
        2>/dev/null || echo "?")
    PREFUND_JSON=$(jq -n \
        --arg addr "$_L2DEP_ADDR_LC" \
        --arg bal "$_l2dep_bal_eth" \
        '[{address: $addr, roles: ["l2Depositor"], balanceEth: $bal, source: "genesis"}]')
fi

GENERATED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

echo "  node0: slot=$N0_SLOT  finalized=$N0_FIN_EPOCH  el_offline=$N0_EL  peers=$N0_PEERS"
echo "  node1: slot=$N1_SLOT  finalized=$N1_FIN_EPOCH  el_offline=$N1_EL  peers=$N1_PEERS"

# --- JSON 생성 ---
mkdir -p "$ARTIFACTS_DIR"

jq -n \
    --argjson chainId "${CHAIN_ID:-1111}" \
    --argjson networkId "${NETWORK_ID:-1111}" \
    --arg n0Rpc "$NODE0_RPC" \
    --arg n1Rpc "$NODE1_RPC" \
    --arg n0Ws "$NODE0_WS" \
    --arg n1Ws "$NODE1_WS" \
    --arg n0Beacon "$NODE0_BEACON" \
    --arg n1Beacon "$NODE1_BEACON" \
    --arg depositAddr "$DEPOSIT_ADDR" \
    --arg feeRecipient "$FEE_ADDR" \
    --arg b0Num "$B0_NUM" \
    --argjson b0Peers "$B0_PEERS" \
    --arg b1Num "$B1_NUM" \
    --argjson b1Peers "$B1_PEERS" \
    --arg n0Slot "$N0_SLOT" \
    --arg n0Dist "$N0_DIST" \
    --argjson n0El "$N0_EL" \
    --argjson n0Peers "$N0_PEERS" \
    --arg n0FinEpoch "$N0_FIN_EPOCH" \
    --arg n0FinRoot "$N0_FIN_ROOT" \
    --arg n1Slot "$N1_SLOT" \
    --arg n1Dist "$N1_DIST" \
    --argjson n1El "$N1_EL" \
    --argjson n1Peers "$N1_PEERS" \
    --arg n1FinEpoch "$N1_FIN_EPOCH" \
    --arg n1FinRoot "$N1_FIN_ROOT" \
    --arg v0 "$V0" \
    --arg v32 "$V32" \
    --argjson prefunded "$PREFUND_JSON" \
    --arg ts "$GENERATED_AT" \
    '{
        chainId:     $chainId,
        networkId:   $networkId,
        executionRpc: {node0: $n0Rpc, node1: $n1Rpc},
        executionWs:  {node0: $n0Ws,  node1: $n1Ws},
        beaconRest:   {node0: $n0Beacon, node1: $n1Beacon},
        depositContractAddress: $depositAddr,
        feeRecipient: $feeRecipient,
        geth: {
            node0: {blockNumber: $b0Num, peerCount: $b0Peers},
            node1: {blockNumber: $b1Num, peerCount: $b1Peers}
        },
        beacon: {
            node0: {
                headSlot:       $n0Slot,
                syncDistance:   $n0Dist,
                elOffline:      $n0El,
                peerCount:      $n0Peers,
                finalizedEpoch: $n0FinEpoch,
                finalizedRoot:  $n0FinRoot
            },
            node1: {
                headSlot:       $n1Slot,
                syncDistance:   $n1Dist,
                elOffline:      $n1El,
                peerCount:      $n1Peers,
                finalizedEpoch: $n1FinEpoch,
                finalizedRoot:  $n1FinRoot
            }
        },
        validators: {
            node0Validator0:  $v0,
            node1Validator32: $v32
        },
        prefundedAccounts: $prefunded,
        generatedAt: $ts
    }' > "$OUTPUT_FILE"

echo ""
echo "=== 생성 완료 ==="
echo "  $OUTPUT_FILE"
echo ""
jq '{chainId, finalizedEpoch: .beacon.node0.finalizedEpoch, prefundedAccounts: (.prefundedAccounts | length)}' \
    "$OUTPUT_FILE"
