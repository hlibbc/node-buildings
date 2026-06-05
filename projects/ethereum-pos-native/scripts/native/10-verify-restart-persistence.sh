#!/usr/bin/env bash
# 10-verify-restart-persistence.sh — 재시작 후 데이터 유지 검증
#
# 사용법:
#   ./10-verify-restart-persistence.sh [--env=<파일>] [--yes]
#
# 옵션:
#   --yes   interactive 확인 없이 바로 실행 (CI/자동화 환경용)
#
# 검증 항목:
#   - 재시작 전 blockNumber 기록
#   - stop → start 수행
#   - 재시작 후 blockNumber 유지 또는 증가 확인
#   - finalized epoch 유지 또는 진행 확인
#   - chaindata / beaconchaindata 디렉토리 유지 확인
#   - genesis.ssz 보존 확인
#   - 서비스 active 상태 확인
#
# 주의: 이 스크립트는 실제로 서비스를 재시작합니다.
#       운영 중인 노드에서 실행 시 약 30초간 서비스 중단이 발생합니다.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"

# --- 인수 파싱 ---
ENV_FILE="$PROJECT_DIR/.env"
YES_MODE=false
for _arg in "$@"; do
    case "$_arg" in
        --env=*) ENV_FILE="${_arg#*=}" ;;
        --yes)   YES_MODE=true ;;
    esac
done
[ -f "$ENV_FILE" ] || { echo "ERROR: env 파일 없음: $ENV_FILE"; exit 1; }
set -a; source "$ENV_FILE"; set +a
echo "ENV: $ENV_FILE  (NODE_NAME=${NODE_NAME})"

NODE_NAME="${NODE_NAME:?'ERROR: NODE_NAME 미설정'}"
GETH_HTTP_PORT="${GETH_HTTP_PORT:-8545}"
BEACON_REST_PORT="${BEACON_REST_PORT:-3500}"
GETH_URL="http://127.0.0.1:${GETH_HTTP_PORT}"
BEACON_URL="http://127.0.0.1:${BEACON_REST_PORT}"
EXECUTION_ROOT="${EXECUTION_ROOT:-/var/lib/ethereum-pos-native/geth}"
BEACON_ROOT="${BEACON_ROOT:-/var/lib/ethereum-pos-native/prysm-beacon}"
CONFIG_ROOT="${CONFIG_ROOT:-/etc/ethereum-pos-native}"

GETH_SVC="eth-pos-geth-${NODE_NAME}"
BEACON_SVC="eth-pos-beacon-${NODE_NAME}"
VALIDATOR_SVC="eth-pos-validator-${NODE_NAME}"

PASS=0
FAIL=0

_ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
_fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
_info() { echo "  [INFO] $*"; }

_rpc() {
    curl -sf -X POST "$GETH_URL" \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":${2:-[]},\"id\":1}" 2>/dev/null
}
_beacon() {
    curl -sf "${BEACON_URL}$1" 2>/dev/null
}

echo ""
echo "========================================"
echo " restart persistence 검증"
echo " 노드: ${NODE_NAME}"
echo "========================================"
echo ""
echo "주의: 서비스를 실제로 재시작합니다 (약 30초 중단)."
if [ "$YES_MODE" = "true" ]; then
    echo "(--yes 옵션: 확인 건너뜀)"
else
    echo -n "계속하려면 Enter, 취소는 Ctrl+C: "
    read -r _confirm
fi

# =========================================
# 재시작 전 상태 기록
# =========================================
echo ""
echo "--- [1/4] 재시작 전 상태 기록 ---"

BLOCK_BEFORE=$(_rpc "eth_blockNumber" | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
FIN_EPOCH_BEFORE=$(_beacon "/eth/v1/beacon/states/head/finality_checkpoints" \
    | jq -r '.data.finalized.epoch // "0"' 2>/dev/null || echo "0")
BN_BEFORE=$(printf '%d' "${BLOCK_BEFORE}" 2>/dev/null || echo "0")

_info "blockNumber:     $BLOCK_BEFORE ($BN_BEFORE)"
_info "finalized epoch: $FIN_EPOCH_BEFORE"

# chaindata 존재 확인 (재시작 전)
if [ -d "$EXECUTION_ROOT/geth/chaindata" ]; then
    _info "geth chaindata: 존재 ($EXECUTION_ROOT/geth/chaindata)"
    CHAINDATA_EXISTS_BEFORE=true
else
    _info "geth chaindata: 없음 (아직 미초기화)"
    CHAINDATA_EXISTS_BEFORE=false
fi

if [ -d "$BEACON_ROOT/beaconchaindata" ]; then
    _info "beacon data: 존재 ($BEACON_ROOT/beaconchaindata)"
else
    _info "beacon data: 없음 (아직 초기화 전일 수 있음)"
fi

# =========================================
# 재시작
# =========================================
echo ""
echo "--- [2/4] 서비스 재시작 ---"

echo "정지 중 (validator → beacon → geth)..."
for _svc in "$VALIDATOR_SVC" "$BEACON_SVC" "$GETH_SVC"; do
    if systemctl is-active "$_svc" &>/dev/null; then
        systemctl stop "$_svc"
        echo "  정지: $_svc"
    else
        echo "  이미 정지됨: $_svc"
    fi
done
sleep 3

# 데이터 디렉토리가 삭제되지 않았는지 확인 (stop 후)
if [ "$CHAINDATA_EXISTS_BEFORE" = "true" ] && [ ! -d "$EXECUTION_ROOT/geth/chaindata" ]; then
    _fail "stop 후 geth chaindata 삭제됨! normal stop 경로에서 데이터 삭제는 설계 오류"
fi

echo "시작 중 (geth → beacon → validator)..."
systemctl start "$GETH_SVC"
echo "  geth 시작됨. 10초 대기..."
sleep 10

systemctl start "$BEACON_SVC"
echo "  beacon 시작됨. 10초 대기..."
sleep 10

systemctl start "$VALIDATOR_SVC"
echo "  validator 시작됨. 15초 대기..."
sleep 15

# =========================================
# 재시작 후 검증
# =========================================
echo ""
echo "--- [3/4] 재시작 후 검증 ---"

# blockNumber 확인
BLOCK_AFTER=$(_rpc "eth_blockNumber" | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
BN_AFTER=$(printf '%d' "${BLOCK_AFTER}" 2>/dev/null || echo "0")
_info "blockNumber (후): $BLOCK_AFTER ($BN_AFTER)"

if [ "$BN_AFTER" -ge "$BN_BEFORE" ] 2>/dev/null; then
    _ok "blockNumber 유지/증가: $BN_BEFORE → $BN_AFTER"
else
    _fail "blockNumber 감소: $BN_BEFORE → $BN_AFTER (체인 데이터 손실 가능성)"
fi

# finalized epoch 확인
FIN_EPOCH_AFTER=$(_beacon "/eth/v1/beacon/states/head/finality_checkpoints" \
    | jq -r '.data.finalized.epoch // "0"' 2>/dev/null || echo "0")
_info "finalized epoch (후): $FIN_EPOCH_AFTER"

if [[ "$FIN_EPOCH_AFTER" =~ ^[0-9]+$ ]] && [[ "$FIN_EPOCH_BEFORE" =~ ^[0-9]+$ ]]; then
    if [ "$FIN_EPOCH_AFTER" -ge "$FIN_EPOCH_BEFORE" ]; then
        _ok "finalized epoch 유지/진행: $FIN_EPOCH_BEFORE → $FIN_EPOCH_AFTER"
    else
        _fail "finalized epoch 후퇴: $FIN_EPOCH_BEFORE → $FIN_EPOCH_AFTER"
    fi
else
    _info "finalized epoch 비교 불가 (아직 달성 전일 수 있음: before=$FIN_EPOCH_BEFORE, after=$FIN_EPOCH_AFTER)"
fi

# 데이터 디렉토리 유지 확인
if [ -d "$EXECUTION_ROOT/geth/chaindata" ]; then
    _ok "geth chaindata 유지: $EXECUTION_ROOT/geth/chaindata"
else
    _fail "geth chaindata 없어짐: $EXECUTION_ROOT/geth/chaindata"
fi

if [ -d "$BEACON_ROOT/beaconchaindata" ]; then
    _ok "beacon data 유지: $BEACON_ROOT/beaconchaindata"
else
    _info "beacon data 없음 — 재시작 직후 아직 생성 중일 수 있음"
fi

if [ -f "$CONFIG_ROOT/genesis.ssz" ]; then
    _ok "genesis.ssz 보존: $CONFIG_ROOT/genesis.ssz"
else
    _fail "genesis.ssz 없어짐: $CONFIG_ROOT/genesis.ssz"
fi

# =========================================
# 서비스 상태
# =========================================
echo ""
echo "--- [4/4] 서비스 상태 ---"
for _svc in "$GETH_SVC" "$BEACON_SVC" "$VALIDATOR_SVC"; do
    STATUS=$(systemctl is-active "$_svc" 2>/dev/null || echo "inactive")
    if [ "$STATUS" = "active" ]; then
        _ok "[$STATUS] $_svc"
    else
        _fail "[$STATUS] $_svc"
        echo "    로그: journalctl -u $_svc --no-pager -n 20"
    fi
done

# =========================================
# 결과
# =========================================
echo ""
echo "========================================"
echo " 결과 요약"
echo "========================================"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "FAIL 항목 있음. 로그 확인:"
    echo "  journalctl -u $GETH_SVC --no-pager -n 30"
    echo "  journalctl -u $BEACON_SVC --no-pager -n 30"
    exit 1
else
    echo "재시작 persistence 검증 완료."
    exit 0
fi
