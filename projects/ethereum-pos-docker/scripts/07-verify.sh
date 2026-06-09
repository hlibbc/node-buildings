#!/usr/bin/env bash
# 07-verify.sh — finality 및 노드 상태 검증
#
# 사용법:
#   pnpm run verify
#   pnpm run verify -- --allow-waiting    (peer=0, finality=0 WARN 처리)
#   pnpm run verify -- --single-node      (peer=0 WARN, finality FAIL 유지)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

ALLOW_WAITING=false
SINGLE_NODE=false
for _arg in "$@"; do
    case "$_arg" in
        --allow-waiting) ALLOW_WAITING=true ;;
        --single-node)   SINGLE_NODE=true ;;
    esac
done

[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음"; exit 1; }
set -a; source "$ENV_FILE"; set +a

NODE0_RPC="http://localhost:${NODE0_RPC_PORT:-8545}"
NODE1_RPC="http://localhost:${NODE1_RPC_PORT:-8645}"
NODE0_BEACON="http://localhost:${NODE0_BEACON_PORT:-3500}"
NODE1_BEACON="http://localhost:${NODE1_BEACON_PORT:-3600}"
CHAIN_ID="${CHAIN_ID:-1111}"
SLOTS_PER_EPOCH="${SLOTS_PER_EPOCH:-32}"

PASS=0; FAIL=0; WARN=0
_ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
_fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
_warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }
_info() { echo "  [INFO] $*"; }
_finality_fail() {
    if [ "$ALLOW_WAITING" = "true" ]; then _warn "$* (--allow-waiting)";
    else _fail "$* (--allow-waiting 옵션 사용 가능)"; fi
}
_peer_fail() {
    if [ "$ALLOW_WAITING" = "true" ] || [ "$SINGLE_NODE" = "true" ]; then _warn "$*";
    else _fail "$* (--allow-waiting 또는 --single-node 옵션 사용 가능)"; fi
}
_rpc() { curl -sf -X POST "$1" -H 'Content-Type: application/json' -d "{\"jsonrpc\":\"2.0\",\"method\":\"$2\",\"params\":${3:-[]},\"id\":1}" 2>/dev/null; }
_beacon() { curl -sf "${1}${2}" 2>/dev/null; }

echo ""
echo "========================================"
echo " ethereum-pos-docker finality 검증"
[ "$ALLOW_WAITING" = "true" ] && echo " MODE: --allow-waiting"
[ "$SINGLE_NODE" = "true" ]   && echo " MODE: --single-node (단독 노드 — 최종 기준 아님)"
echo "========================================"

# --- Docker 서비스 상태 ---
echo ""
echo "--- Docker 서비스 ---"
for CTR in geth-node0 beacon-node0 validator-node0 geth-node1 beacon-node1 validator-node1; do
    STATUS=$(docker inspect --format '{{.State.Status}}' "$CTR" 2>/dev/null || echo "없음")
    if [ "$STATUS" = "running" ]; then _ok "[$STATUS] $CTR";
    else _fail "[$STATUS] $CTR"; fi
done

# --- Geth 확인 ---
echo ""
echo "--- Geth ---"
for NODE_RPC in "$NODE0_RPC" "$NODE1_RPC"; do
    LABEL="node0"; [ "$NODE_RPC" = "$NODE1_RPC" ] && LABEL="node1"
    CHAIN_RES=$(_rpc "$NODE_RPC" "eth_chainId" || echo "")
    if [ -n "$CHAIN_RES" ]; then
        CHAIN_HEX=$(echo "$CHAIN_RES" | jq -r '.result // "?"')
        CHAIN_DEC=$(printf '%d' "$CHAIN_HEX" 2>/dev/null || echo "?")
        if [ "$CHAIN_DEC" = "$CHAIN_ID" ]; then _ok "[$LABEL] chainId=$CHAIN_HEX ($CHAIN_DEC)";
        else _fail "[$LABEL] chainId 불일치: $CHAIN_DEC ≠ $CHAIN_ID"; fi
        BLOCK=$(_rpc "$NODE_RPC" "eth_blockNumber" | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
        _info "[$LABEL] blockNumber=$BLOCK"
        PEER_HEX=$(_rpc "$NODE_RPC" "net_peerCount" | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
        PEER_CNT=$(printf '%d' "$PEER_HEX" 2>/dev/null || echo "0")
        if [ "$PEER_CNT" -gt 0 ] 2>/dev/null; then _ok "[$LABEL] peerCount=$PEER_CNT";
        else _peer_fail "[$LABEL] peerCount=0"; fi
    else
        _fail "[$LABEL] Geth RPC 응답 없음($NODE_RPC)"
    fi
done

# --- Beacon 확인 ---
echo ""
echo "--- Beacon ---"
for NODE_BEACON in "$NODE0_BEACON" "$NODE1_BEACON"; do
    LABEL="node0"; [ "$NODE_BEACON" = "$NODE1_BEACON" ] && LABEL="node1"
    HEALTH=$(curl -sf "${NODE_BEACON}/eth/v1/node/health" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    if [ "$HEALTH" = "200" ] || [ "$HEALTH" = "206" ]; then _ok "[$LABEL] health HTTP$HEALTH";
    else _fail "[$LABEL] health HTTP$HEALTH ($NODE_BEACON)"; fi

    PEER_COUNT=$(curl -sf "${NODE_BEACON}/eth/v1/node/peers" 2>/dev/null \
        | jq '.data | length' 2>/dev/null || echo "0")
    if [ "${PEER_COUNT:-0}" -gt 0 ] 2>/dev/null; then _ok "[$LABEL] beacon peers=$PEER_COUNT";
    else _peer_fail "[$LABEL] beacon peers=0"; fi

    SYNC=$(_beacon "$NODE_BEACON" "/eth/v1/node/syncing" || echo "")
    if [ -n "$SYNC" ]; then
        HEAD=$(echo "$SYNC" | jq -r '.data.head_slot // "0"')
        if [[ "$HEAD" =~ ^[0-9]+$ ]] && [ "$HEAD" -gt 0 ]; then
            EPOCH=$((HEAD / SLOTS_PER_EPOCH))
            _ok "[$LABEL] slot=$HEAD (epoch=$EPOCH)"
        else
            _warn "[$LABEL] slot=0 — beacon 기동 중"
        fi
    fi

    FIN=$(_beacon "$NODE_BEACON" "/eth/v1/beacon/states/head/finality_checkpoints" || echo "")
    if [ -n "$FIN" ]; then
        FIN_EPOCH=$(echo "$FIN" | jq -r '.data.finalized.epoch // "0"')
        FIN_ROOT=$(echo "$FIN"  | jq -r '.data.finalized.root  // "N/A"')
        _info "[$LABEL] finalized epoch=$FIN_EPOCH"
        _info "[$LABEL] finalized root=$FIN_ROOT"
        if [[ "$FIN_EPOCH" =~ ^[0-9]+$ ]] && [ "$FIN_EPOCH" -gt 0 ]; then
            _ok "[$LABEL] finalized epoch=$FIN_EPOCH"
        else
            _finality_fail "[$LABEL] finalized epoch=0 — finality 미달성"
        fi
    else
        _fail "[$LABEL] finality_checkpoints 응답 없음"
    fi
done

# --- Validator 확인 ---
echo ""
echo "--- Validator (index 0, 32) ---"
for IDX_BEACON in "0|$NODE0_BEACON|node0" "32|$NODE1_BEACON|node1"; do
    IFS='|' read -r IDX BURL LBL <<< "$IDX_BEACON"
    VAL=$(_beacon "$BURL" "/eth/v1/beacon/states/head/validators/${IDX}" || echo "")
    if [ -n "$VAL" ]; then
        STATUS=$(echo "$VAL" | jq -r '.data.status // "N/A"')
        echo "$STATUS" | grep -qi "active" && _ok "[$LBL] validator[$IDX] $STATUS" \
            || _warn "[$LBL] validator[$IDX] $STATUS"
    else
        _warn "[$LBL] validator[$IDX] 조회 실패 (beacon 기동 중일 수 있음)"
    fi
done

# --- L2 Depositor Account ---
echo ""
echo "--- L2 Depositor Account ---"

_L2DEP="${L2_DEPOSITOR_ADDRESS:-}"
if [ -z "$_L2DEP" ]; then
    _info "L2_DEPOSITOR_ADDRESS not set; skip L2 depositor balance check"
else
    if ! printf '%s' "$_L2DEP" | grep -qE '^0x[0-9a-fA-F]{40}$'; then
        _fail "[l2Depositor] L2_DEPOSITOR_ADDRESS 잘못된 주소 형식: $_L2DEP"
    else
        _l2dep_bal=$(_rpc "$NODE0_RPC" "eth_getBalance" "[\"$_L2DEP\", \"latest\"]" \
            | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
        _l2dep_stripped=$(printf '%s' "$_l2dep_bal" | sed 's/^0x//' | sed 's/^0*//')
        if [ -n "$_l2dep_stripped" ]; then
            _l2dep_eth=$(node -e \
                "try{process.stdout.write((BigInt('${_l2dep_bal}')/10n**18n).toString())}catch(e){process.stdout.write('?')}" \
                2>/dev/null || echo "?")
            _ok "[l2Depositor] $_L2DEP  balance=${_l2dep_eth} ETH"
        else
            _fail "[l2Depositor] $_L2DEP  balance=0 (prefund는 genesis generation time에만 반영됨 — clean → generate → init → start 재구축 필요)"
        fi
    fi
fi

echo ""
echo "========================================"
echo " 결과: PASS=$PASS  FAIL=$FAIL  WARN=$WARN"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
