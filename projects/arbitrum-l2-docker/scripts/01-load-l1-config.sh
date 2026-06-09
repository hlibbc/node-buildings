#!/usr/bin/env bash
# 01-load-l1-config.sh — L1 artifact 로드, 검증, resolved-l1-config.env 생성
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project

echo "=== 01-load-l1-config (arbitrum-l2-docker) ==="
echo ""

L1_INFO_FILE="${L1_CHAIN_INFO_PATH:-$PROJECT_DIR/config/l1-chain-info.json}"

# ---------------------------------------------------------------
# artifact 존재 확인
# ---------------------------------------------------------------
echo "--- L1 artifact 로드 ---"
if [ ! -f "$L1_INFO_FILE" ]; then
    echo "[ERROR] l1-chain-info.json 없음: $L1_INFO_FILE"
    echo "        복사: cp ../ethereum-pos-docker/artifacts/l1-chain-info.json ./config/"
    exit 1
fi
_ok "l1-chain-info.json 로드: $L1_INFO_FILE"

# ---------------------------------------------------------------
# 기본 필드 추출
# ---------------------------------------------------------------
ARTIFACT_CHAIN_ID=$(jq -r '.chainId'              "$L1_INFO_FILE")
ARTIFACT_RPC_N0=$(jq -r '.executionRpc.node0'     "$L1_INFO_FILE")
ARTIFACT_WS_N0=$(jq -r  '.executionWs.node0'      "$L1_INFO_FILE")

_info "artifact chainId       = $ARTIFACT_CHAIN_ID"
_info "artifact executionRpc  = $ARTIFACT_RPC_N0"
_info "artifact executionWs   = $ARTIFACT_WS_N0"

# ---------------------------------------------------------------
# .env override 반영
# ---------------------------------------------------------------
echo ""
echo "--- endpoint 결정 ---"
PARENT_CHAIN_RPC="${L1_RPC_URL:-$ARTIFACT_RPC_N0}"
PARENT_CHAIN_WS="${L1_WS_URL:-$ARTIFACT_WS_N0}"
PARENT_CHAIN_ID="${L1_CHAIN_ID:-$ARTIFACT_CHAIN_ID}"

if [ -n "${L1_RPC_URL:-}" ]; then
    _info "PARENT_CHAIN_RPC = $PARENT_CHAIN_RPC  (L1_RPC_URL override)"
else
    _info "PARENT_CHAIN_RPC = $PARENT_CHAIN_RPC  (artifact)"
fi
if [ -n "${L1_WS_URL:-}" ]; then
    _info "PARENT_CHAIN_WS  = $PARENT_CHAIN_WS  (L1_WS_URL override)"
else
    _info "PARENT_CHAIN_WS  = $PARENT_CHAIN_WS  (artifact)"
fi
_info "PARENT_CHAIN_ID  = $PARENT_CHAIN_ID"

# ---------------------------------------------------------------
# L1 RPC 연결 확인 + chainId 검증
# ---------------------------------------------------------------
echo ""
echo "--- L1 RPC 연결 확인 ---"
RPC_RESULT=$(_rpc "$PARENT_CHAIN_RPC" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
if [ -z "$RPC_RESULT" ]; then
    _fail "L1 RPC 응답 없음: $PARENT_CHAIN_RPC"
    echo "[ERROR] L1 RPC에 연결할 수 없습니다."
    exit 1
fi

CHAIN_ID_HEX=$(printf '%s' "$RPC_RESULT" | jq -r '.result // empty' 2>/dev/null)
if [ -z "$CHAIN_ID_HEX" ]; then
    _fail "eth_chainId 응답 파싱 실패: $RPC_RESULT"
    exit 1
fi
CHAIN_ID_RPC=$(hex_to_dec "$CHAIN_ID_HEX")

if [ "$CHAIN_ID_RPC" = "$PARENT_CHAIN_ID" ]; then
    _ok "chainId 일치: $PARENT_CHAIN_ID (RPC=$CHAIN_ID_RPC, config=$PARENT_CHAIN_ID)"
else
    _fail "chainId 불일치: config=$PARENT_CHAIN_ID, RPC=$CHAIN_ID_RPC"
    echo "[ERROR] L1 RPC의 chainId가 artifact/설정과 다릅니다."
    exit 1
fi

# ---------------------------------------------------------------
# L1 finality 확인
# ---------------------------------------------------------------
echo ""
echo "--- L1 finality 확인 ---"
# finalizedEpoch may be string or number
FINALIZED_EPOCH=$(jq -r '
    .beacon.node0.finalizedEpoch |
    if type == "string" then tonumber else . end
' "$L1_INFO_FILE" 2>/dev/null || echo "0")

EL_OFFLINE=$(jq -r '.beacon.node0.elOffline // true' "$L1_INFO_FILE")

if [ "$EL_OFFLINE" = "false" ]; then
    _ok "beacon node0 EL offline = false"
else
    _fail "beacon node0 elOffline = $EL_OFFLINE  (EL offline 상태)"
fi

FINALIZED_EPOCH_INT=$(printf '%d' "${FINALIZED_EPOCH}" 2>/dev/null || echo 0)
if [ "$FINALIZED_EPOCH_INT" -gt 0 ]; then
    _ok "finalizedEpoch = $FINALIZED_EPOCH_INT  (finality 달성)"
else
    _fail "finalizedEpoch = 0  (finality 미달성 — L1이 완전히 기동되지 않았을 수 있음)"
fi

# ---------------------------------------------------------------
# prefundedAccounts에서 l2Depositor 확인
# ---------------------------------------------------------------
echo ""
echo "--- L2 depositor 확인 ---"
DEPOSITOR_IN_ARTIFACT=$(jq -r '
    .prefundedAccounts[]? |
    select(.roles[]? | ascii_downcase | contains("l2depositor")) |
    .address
' "$L1_INFO_FILE" 2>/dev/null | head -1)

if [ -z "$DEPOSITOR_IN_ARTIFACT" ]; then
    _fail "l1-chain-info.json에 l2Depositor 계정 없음"
    _info "  L1 프로젝트에서 L2_DEPOSITOR_ADDRESS를 설정하고 artifact를 재생성하세요."
else
    _ok "artifact l2Depositor: $DEPOSITOR_IN_ARTIFACT"

    # .env의 L2_DEPOSITOR_ADDRESS와 비교 (대소문자 무시)
    ENV_DEP_LC=$(printf '%s' "${L2_DEPOSITOR_ADDRESS:-}" | tr '[:upper:]' '[:lower:]')
    ART_DEP_LC=$(printf '%s' "$DEPOSITOR_IN_ARTIFACT" | tr '[:upper:]' '[:lower:]')
    if [ -z "$ENV_DEP_LC" ]; then
        _warn "L2_DEPOSITOR_ADDRESS 미설정 — .env를 확인하세요"
    elif [ "$ENV_DEP_LC" = "$ART_DEP_LC" ]; then
        _ok "L2_DEPOSITOR_ADDRESS 일치"
    else
        _fail "L2_DEPOSITOR_ADDRESS 불일치"
        _info "  .env: $ENV_DEP_LC"
        _info "  artifact: $ART_DEP_LC"
    fi
fi

# ---------------------------------------------------------------
# depositor L1 잔액 확인
# ---------------------------------------------------------------
if [ -n "$DEPOSITOR_IN_ARTIFACT" ]; then
    DEP_LOWER=$(printf '%s' "$DEPOSITOR_IN_ARTIFACT" | tr '[:upper:]' '[:lower:]')
    BAL_RESULT=$(_rpc "$PARENT_CHAIN_RPC" \
        "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$DEP_LOWER\",\"latest\"],\"id\":1}")
    BAL_HEX=$(printf '%s' "$BAL_RESULT" | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
    if hex_is_zero "$BAL_HEX"; then
        _fail "l2Depositor L1 balance = 0  (L1에서 ETH 없음)"
    else
        _ok "l2Depositor L1 balance = $(format_wei_eth "$BAL_HEX")"
    fi
fi

# ---------------------------------------------------------------
# resolved-l1-config.env 생성
# ---------------------------------------------------------------
echo ""
echo "--- resolved-l1-config.env 생성 ---"
RESOLVED_FILE="$PROJECT_DIR/config/resolved-l1-config.env"
cat > "$RESOLVED_FILE" <<EOF
# Auto-generated by 01-load-l1-config.sh — do not edit manually
PARENT_CHAIN_RPC="${PARENT_CHAIN_RPC}"
PARENT_CHAIN_WS="${PARENT_CHAIN_WS}"
PARENT_CHAIN_ID="${PARENT_CHAIN_ID}"
L1_DEPOSITOR_ADDRESS="${DEPOSITOR_IN_ARTIFACT:-}"
EOF
_ok "config/resolved-l1-config.env 생성 완료"
_info "  PARENT_CHAIN_RPC = $PARENT_CHAIN_RPC"
_info "  PARENT_CHAIN_WS  = $PARENT_CHAIN_WS"
_info "  PARENT_CHAIN_ID  = $PARENT_CHAIN_ID"

# ---------------------------------------------------------------
# 결과
# ---------------------------------------------------------------
echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "L1 config 로드 완료."
else
    echo "ERROR: $ERRORS 개 항목 실패."
    exit 1
fi
