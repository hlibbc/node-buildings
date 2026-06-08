#!/usr/bin/env bash
# 09-verify-finality.sh — finality 및 노드 상태 종합 검증
#
# 사용법:
#   ./09-verify-finality.sh [--env=<파일>] [--allow-waiting] [--single-node]
#
# 옵션:
#   --allow-waiting  peer=0, finality 미달성을 FAIL 대신 WARN으로 처리
#                    (노드 시작 직후 상태 확인 시 사용)
#                    기본값: 없음 → 미달성 시 exit 1
#   --single-node    peer=0을 WARN으로 처리 (단일 노드 임시 검증용)
#                    주의: 단일 노드는 finality를 달성할 수 없으므로
#                          --single-node 통과는 최종 성공 기준이 아닙니다.
#                          반드시 2-node peer 연결 후 최종 검증을 수행하세요.
#
# 성공 기준:
#   - 기본 모드: net_peerCount≥1, finalized epoch>0 모두 필요
#   - --allow-waiting: 위 항목 WARN 허용 (초기 기동 확인용)
#   - --single-node: peer=0 WARN 허용, finality는 여전히 FAIL (단독 finality 불가)
#
# 검증 항목:
#   - geth/prysm 버전
#   - eth_chainId, eth_blockNumber 증가
#   - net_peerCount          ← 0이면 기본 FAIL
#   - beacon 노드 health, slot, epoch
#   - finalized checkpoint   ← epoch=0이면 기본 FAIL
#   - finalized block header ← slot=0이면 기본 FAIL
#   - validator active 상태
#   - validator index 중복 없음
#   - 데이터 디렉토리 유지 여부
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"

# --- 인수 파싱 ---
ENV_FILE="$PROJECT_DIR/.env"
ALLOW_WAITING=false
SINGLE_NODE=false
for _arg in "$@"; do
    case "$_arg" in
        --env=*)           ENV_FILE="${_arg#*=}" ;;
        --allow-waiting)   ALLOW_WAITING=true ;;
        --single-node)     SINGLE_NODE=true ;;
    esac
done

# --- env 로드 ---
[ -f "$ENV_FILE" ] || { echo "ERROR: env 파일 없음: $ENV_FILE"; exit 1; }
set -a; source "$ENV_FILE"; set +a
echo "ENV: $ENV_FILE  (NODE_NAME=${NODE_NAME:-?})"
[ "$ALLOW_WAITING" = "true" ] && echo "MODE: --allow-waiting (peer=0/finality 미달성 WARN 허용)"
if [ "$SINGLE_NODE" = "true" ]; then
    echo "MODE: --single-node (peer=0 WARN 허용 — 최종 성공 기준 아님)"
    echo "      단일 노드는 2/3 validator quorum 달성 불가 → finality 불가"
    echo "      반드시 2-node 구성 후 최종 검증하세요."
fi

GETH_HTTP_PORT="${GETH_HTTP_PORT:-8545}"
BEACON_REST_PORT="${BEACON_REST_PORT:-3500}"
GETH_URL="http://127.0.0.1:${GETH_HTTP_PORT}"
BEACON_URL="http://127.0.0.1:${BEACON_REST_PORT}"
VALIDATOR_START_INDEX="${VALIDATOR_START_INDEX:-0}"
VALIDATOR_COUNT="${VALIDATOR_COUNT:-32}"
CHAIN_ID="${CHAIN_ID:-1111}"

# jq 확인
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq 없음. 설치: apt install jq"
    exit 1
fi

PASS=0
FAIL=0
WARN=0

_ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
_fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
_warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }
_info() { echo "  [INFO] $*"; }

# finality 관련 실패/경고 분기 헬퍼
_finality_fail() {
    if [ "$ALLOW_WAITING" = "true" ]; then
        _warn "$* (--allow-waiting 모드)"
    else
        _fail "$* (--allow-waiting 옵션으로 WARN으로 처리 가능)"
    fi
}

# peer count 관련 실패/경고 분기 헬퍼
# --allow-waiting 또는 --single-node 시 WARN, 기본은 FAIL
_peer_fail() {
    if [ "$ALLOW_WAITING" = "true" ] || [ "$SINGLE_NODE" = "true" ]; then
        _warn "$*"
    else
        _fail "$* (--allow-waiting 또는 --single-node 옵션으로 WARN 처리 가능)"
    fi
}

_rpc() {
    curl -sf -X POST "$GETH_URL" \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":${2:-[]},\"id\":1}" \
        2>/dev/null
}

_beacon() {
    curl -sf "${BEACON_URL}$1" 2>/dev/null
}

echo ""
echo "========================================"
echo " ethereum-pos-native finality 검증"
echo " 노드: ${NODE_NAME:-?}"
echo "========================================"

# ----------------------------------------
echo ""
echo "--- 바이너리 버전 ---"
if command -v geth &>/dev/null; then
    GETH_VER=$(geth version 2>/dev/null | grep "Version:" | head -1 | awk '{print $2}')
    _ok "geth: $GETH_VER"
else
    _fail "geth 없음"
fi

if command -v beacon-chain &>/dev/null; then
    BEACON_VER=$(beacon-chain --version 2>/dev/null | head -1 || echo "확인 실패")
    _ok "beacon-chain: $BEACON_VER"
else
    _fail "beacon-chain 없음"
fi

if command -v validator &>/dev/null; then
    VAL_VER=$(validator --version 2>/dev/null | head -1 || echo "확인 실패")
    _ok "validator: $VAL_VER"
else
    _fail "validator 없음"
fi

# ----------------------------------------
echo ""
echo "--- Geth RPC ---"
CHAIN_ID_RES=$(_rpc "eth_chainId" || echo "")
if [ -n "$CHAIN_ID_RES" ]; then
    CHAIN_ID_HEX=$(echo "$CHAIN_ID_RES" | jq -r '.result')
    CHAIN_ID_DEC=$((16#${CHAIN_ID_HEX#0x}))
    if [ "$CHAIN_ID_DEC" = "$CHAIN_ID" ]; then
        _ok "eth_chainId: $CHAIN_ID_HEX ($CHAIN_ID_DEC)"
    else
        _fail "eth_chainId 불일치: $CHAIN_ID_HEX ($CHAIN_ID_DEC) ≠ $CHAIN_ID"
    fi
else
    _fail "Geth RPC 응답 없음 ($GETH_URL)"
fi

# blockNumber 증가 확인
BLOCK1_RES=$(_rpc "eth_blockNumber" || echo "")
if [ -n "$BLOCK1_RES" ]; then
    BLOCK1_HEX=$(echo "$BLOCK1_RES" | jq -r '.result // "0x0"')
    _info "blockNumber (1차): $BLOCK1_HEX"
    sleep 15
    BLOCK2_RES=$(_rpc "eth_blockNumber" || echo "")
    if [ -n "$BLOCK2_RES" ]; then
        BLOCK2_HEX=$(echo "$BLOCK2_RES" | jq -r '.result // "0x0"')
        _info "blockNumber (15초 후): $BLOCK2_HEX"
        if [ "$BLOCK1_HEX" != "$BLOCK2_HEX" ] && [ "$BLOCK2_HEX" != "0x0" ]; then
            _ok "블록 증가 확인됨"
        else
            _warn "블록이 증가하지 않음 — peer 연결 또는 beacon 상태 확인"
        fi
    fi
fi

# peer count — 기본 모드에서 0이면 FAIL
PEER_RES=$(_rpc "net_peerCount" || echo "")
if [ -n "$PEER_RES" ]; then
    PEER_COUNT_HEX=$(echo "$PEER_RES" | jq -r '.result // "0x0"')
    PEER_COUNT=$(printf '%d' "${PEER_COUNT_HEX}" 2>/dev/null || echo "0")
    if [ "$PEER_COUNT" -gt 0 ] 2>/dev/null; then
        _ok "net_peerCount: $PEER_COUNT"
    else
        _peer_fail "net_peerCount: 0 — peer 연결 없음. docs/ethereum-pos-native/peer-connection.md 참조"
    fi
else
    _fail "net_peerCount 응답 없음"
fi

# ----------------------------------------
echo ""
echo "--- Beacon REST API ---"
HEALTH_CODE=$(curl -sf "${BEACON_URL}/eth/v1/node/health" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
if [ "$HEALTH_CODE" = "200" ] || [ "$HEALTH_CODE" = "206" ]; then
    _ok "beacon health: HTTP $HEALTH_CODE"
else
    _fail "beacon health: HTTP $HEALTH_CODE ($BEACON_URL)"
fi

# beacon peer count — 기본 모드에서 0이면 FAIL
BEACON_PEERS_JSON=$(_beacon "/eth/v1/node/peers" || echo "")
if [ -n "$BEACON_PEERS_JSON" ]; then
    BEACON_PEER_COUNT=$(echo "$BEACON_PEERS_JSON" | jq '.data | length' 2>/dev/null || echo "0")
    if [ "${BEACON_PEER_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        _ok "beacon peers: ${BEACON_PEER_COUNT}"
    else
        _peer_fail "beacon peers: 0 — beacon peer 연결 없음. P2P_ADVERTISE_IP 및 peer-connection.md 확인"
    fi
else
    _fail "beacon peers endpoint 응답 없음 (${BEACON_URL}/eth/v1/node/peers)"
fi

# slot / epoch
SYNC_JSON=$(_beacon "/eth/v1/node/syncing" || echo "")
if [ -n "$SYNC_JSON" ]; then
    HEAD_SLOT=$(echo "$SYNC_JSON" | jq -r '.data.head_slot // "0"')
    IS_SYNC=$(echo "$SYNC_JSON"  | jq -r '.data.is_syncing // "N/A"')
    # 숫자인 경우에만 epoch 계산
    if [[ "$HEAD_SLOT" =~ ^[0-9]+$ ]]; then
        CURRENT_EPOCH=$(( HEAD_SLOT / ${SLOTS_PER_EPOCH:-32} ))
        _info "head_slot: $HEAD_SLOT  (epoch: $CURRENT_EPOCH)"
        if [ "$HEAD_SLOT" -gt 0 ]; then
            _ok "slot 진행 중 (slot=$HEAD_SLOT, epoch=$CURRENT_EPOCH)"
        else
            _warn "slot=0 — beacon 아직 시작 중이거나 genesis 도달 전"
        fi
    else
        _warn "head_slot 값 불명확: $HEAD_SLOT"
    fi
    _info "is_syncing: $IS_SYNC"
else
    _fail "beacon syncing endpoint 응답 없음"
fi

# finalized checkpoint
FIN_JSON=$(_beacon "/eth/v1/beacon/states/head/finality_checkpoints" || echo "")
if [ -n "$FIN_JSON" ]; then
    FIN_EPOCH=$(echo "$FIN_JSON"  | jq -r '.data.finalized.epoch // "N/A"')
    FIN_ROOT=$(echo "$FIN_JSON"   | jq -r '.data.finalized.root  // "N/A"')
    JUST_EPOCH=$(echo "$FIN_JSON" | jq -r '.data.current_justified.epoch // "N/A"')
    _info "current_justified epoch: $JUST_EPOCH"
    _info "finalized epoch:        $FIN_EPOCH"
    _info "finalized root:         $FIN_ROOT"
    if [[ "$FIN_EPOCH" =~ ^[0-9]+$ ]] && [ "$FIN_EPOCH" -gt 0 ]; then
        _ok "finalized checkpoint 확인: epoch=$FIN_EPOCH"
    else
        _finality_fail "finalized epoch=0 — finality 미달성. peer 연결 및 validator 참여 확인 필요"
    fi
else
    _fail "finality_checkpoints 응답 없음"
fi

# finalized block header
FIN_HEADER=$(_beacon "/eth/v1/beacon/headers/finalized" || echo "")
if [ -n "$FIN_HEADER" ]; then
    FIN_SLOT=$(echo "$FIN_HEADER" | jq -r '.data.header.message.slot // "0"')
    FIN_BLOCK_ROOT=$(echo "$FIN_HEADER" | jq -r '.data.root // "N/A"')
    _info "finalized block slot: $FIN_SLOT"
    _info "finalized block root: $FIN_BLOCK_ROOT"
    if [[ "$FIN_SLOT" =~ ^[0-9]+$ ]] && [ "$FIN_SLOT" -gt 0 ]; then
        _ok "finalized block header 조회 성공 (slot=$FIN_SLOT)"
    else
        _finality_fail "finalized block slot=0 — finality 미달성"
    fi
else
    _fail "finalized block header 응답 없음"
fi

# ----------------------------------------
echo ""
echo "--- Validator 상태 ---"
_info "이 노드 validator 범위: index ${VALIDATOR_START_INDEX} ~ $((VALIDATOR_START_INDEX + VALIDATOR_COUNT - 1))"

# 첫 번째 validator 상태 확인
FIRST_IDX="$VALIDATOR_START_INDEX"
VAL_JSON=$(_beacon "/eth/v1/beacon/states/head/validators/${FIRST_IDX}" || echo "")
if [ -n "$VAL_JSON" ]; then
    VAL_STATUS=$(echo "$VAL_JSON" | jq -r '.data.status // "N/A"')
    VAL_BALANCE=$(echo "$VAL_JSON" | jq -r '.data.balance // "N/A"')
    _info "validator[$FIRST_IDX]: status=$VAL_STATUS, balance=$VAL_BALANCE"
    if echo "$VAL_STATUS" | grep -qi "active"; then
        _ok "validator[$FIRST_IDX] active"
    else
        _warn "validator[$FIRST_IDX] 상태: $VAL_STATUS (아직 active 아님)"
    fi
else
    _warn "validator[$FIRST_IDX] 조회 실패 (beacon 응답 없음 또는 genesis 이전)"
fi

# ----------------------------------------
echo ""
echo "--- Validator index 범위 중복 검증 ---"
# node0: 0~31, node1: 32~63 (겹치지 않아야 함)
NODE0_START=0
NODE0_END=31
NODE1_START=32
NODE1_END=63
THIS_START="$VALIDATOR_START_INDEX"
THIS_END=$((VALIDATOR_START_INDEX + VALIDATOR_COUNT - 1))

_info "이 노드 범위: $THIS_START ~ $THIS_END"
_info "node0 예상: $NODE0_START ~ $NODE0_END"
_info "node1 예상: $NODE1_START ~ $NODE1_END"

# node0 범위와 node1 범위가 겹치지 않는지 확인 (정수 범위 교집합)
NODE0_NODE1_OVERLAP=0
if [ "$NODE0_START" -le "$NODE1_END" ] && [ "$NODE0_END" -ge "$NODE1_START" ]; then
    NODE0_NODE1_OVERLAP=1
fi

if [ "$NODE0_NODE1_OVERLAP" -eq 1 ]; then
    _fail "validator 범위 중복: node0($NODE0_START~$NODE0_END) ↔ node1($NODE1_START~$NODE1_END)"
else
    _ok "node0/node1 validator 범위 비중복: node0=$NODE0_START~$NODE0_END, node1=$NODE1_START~$NODE1_END"
fi

# 이 노드의 범위가 정해진 범위(0~31 또는 32~63)인지 확인
if { [ "$THIS_START" = "$NODE0_START" ] && [ "$THIS_END" = "$NODE0_END" ]; } || \
   { [ "$THIS_START" = "$NODE1_START" ] && [ "$THIS_END" = "$NODE1_END" ]; }; then
    _ok "이 노드 validator 범위 정상: $THIS_START ~ $THIS_END"
else
    _warn "이 노드 validator 범위 확인 필요: $THIS_START ~ $THIS_END (node0=0~31, node1=32~63 권장)"
fi

# ----------------------------------------
echo ""
echo "--- 재시작 후 데이터 유지 확인 ---"
CONFIG_ROOT="${CONFIG_ROOT:-/etc/ethereum-pos-native}"
EXECUTION_ROOT="${EXECUTION_ROOT:-/var/lib/ethereum-pos-native/geth}"
BEACON_ROOT="${BEACON_ROOT:-/var/lib/ethereum-pos-native/prysm-beacon}"

if [ -d "$EXECUTION_ROOT/geth/chaindata" ]; then
    _ok "geth chaindata 존재: $EXECUTION_ROOT/geth/chaindata"
else
    _fail "geth chaindata 없음: $EXECUTION_ROOT/geth/chaindata"
fi

if [ -d "$BEACON_ROOT/beaconchaindata" ]; then
    _ok "beacon data 존재: $BEACON_ROOT/beaconchaindata"
else
    _warn "beacon data 없음: $BEACON_ROOT/beaconchaindata (아직 생성 전일 수 있음)"
fi

if [ -f "$CONFIG_ROOT/genesis.ssz" ]; then
    _ok "genesis.ssz 보존: $CONFIG_ROOT/genesis.ssz"
else
    _fail "genesis.ssz 없음: $CONFIG_ROOT/genesis.ssz"
fi

# ----------------------------------------
echo ""
echo "========================================"
echo " 결과 요약"
echo "========================================"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  WARN: $WARN"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "FAIL 항목이 있습니다. 위 내용을 확인하세요."
    echo "도움말: docs/ethereum-pos-native/finality-check.md"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "경고 항목이 있습니다. peer 연결 및 finality 진행을 기다리세요."
    echo "finality 기대 시간: validator 2개 epoch 참여 후 (약 6~10분)"
    exit 0
else
    echo "모든 검증 통과."
    exit 0
fi
