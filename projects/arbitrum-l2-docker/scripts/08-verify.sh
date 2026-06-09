#!/usr/bin/env bash
# 08-verify.sh — L1/L2 전체 동작 검증
#
# 검증 항목:
#   [L1] RPC 응답, chainId, depositor 잔액
#   [L1] contracts code 존재 (rollup, bridge, inbox, outbox, sequencerInbox)
#   [L1] sequencer start 이후 batch posting 이벤트 (sequencerInbox)
#   [L1] sequencer start 이후 assertion 이벤트 (rollup)
#   [L2] RPC 응답, chainId
#   [L2] 블록 생성 확인 (6초 증분)
#   [L2] 계정 잔액 (depositor, 각 role)
#   [L2] sequencer feed port 응답
#   [CONFIG] batch-poster.enable = true  (FAIL)
#   [CONFIG] staker.enable = true        (FAIL — 정책 위반은 WARN 불가)
#   [DOCKER] sequencer 서비스 상태
#
# fromBlock 기준:
#   artifacts/l2-start.json의 l1BlockAtStart 사용
#   파일이 없으면 0x0 사용 (WARN)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project
load_resolved_l1_config

echo "=== 08-verify (arbitrum-l2-docker) ==="
echo ""

L2_RPC="http://localhost:${L2_RPC_PORT:-8547}"
L2_FEED_PORT_VAL="${L2_FEED_PORT:-9642}"

# Helper: eth_getCode로 컨트랙트 존재 확인
check_contract_code() {
    local name="$1" addr="$2" rpc="$3"
    if [ -z "$addr" ] || [ "$addr" = "null" ]; then
        _warn "$name: 주소 없음 (건너뜀)"
        return
    fi
    local result code
    result=$(_rpc "$rpc" "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$addr\",\"latest\"],\"id\":1}")
    code=$(echo "$result" | jq -r '.result // empty' 2>/dev/null || echo "")
    if [ "${#code}" -gt 4 ]; then
        _ok "$name ($addr): code 존재"
    else
        _fail "$name ($addr): code 없음 (배포 미완료?)"
    fi
}

# Helper: 포트 열려 있는지 확인
check_port_open() {
    local port="$1"
    if command -v nc &>/dev/null; then
        nc -z -w 2 localhost "$port" 2>/dev/null && return 0 || return 1
    else
        (echo "" > /dev/tcp/localhost/"$port") 2>/dev/null && return 0 || return 1
    fi
}

# l2-start.json에서 L1 시작 블록 추출 (fromBlock 기준)
L1_FROM_HEX="0x0"
if [ -f "$PROJECT_DIR/artifacts/l2-start.json" ]; then
    L1_START_BLOCK=$(jq -r '.l1BlockAtStart // 0' "$PROJECT_DIR/artifacts/l2-start.json")
    L1_FROM_HEX=$(printf '0x%x' "$L1_START_BLOCK")
    _info "l2-start.json: l1BlockAtStart = $L1_START_BLOCK  (fromBlock=$L1_FROM_HEX)"
else
    _warn "artifacts/l2-start.json 없음 — fromBlock=0x0 사용 (과거 이벤트 포함 가능)"
fi
echo ""

# ---------------------------------------------------------------
# [L1] RPC 연결 및 chainId
# ---------------------------------------------------------------
echo "=== [L1] ==="
echo ""
echo "--- L1 RPC 연결 ---"
L1_RESP=$(_rpc "$PARENT_CHAIN_RPC" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
L1_CHAIN_ID_HEX=$(echo "$L1_RESP" | jq -r '.result // empty' 2>/dev/null || echo "")
if [ -z "$L1_CHAIN_ID_HEX" ]; then
    _fail "L1 RPC ($PARENT_CHAIN_RPC) 응답 없음"
else
    L1_CHAIN_ID_DEC=$(hex_to_dec "$L1_CHAIN_ID_HEX")
    if [ "$L1_CHAIN_ID_DEC" = "$PARENT_CHAIN_ID" ]; then
        _ok "L1 RPC 응답 (chainId=$L1_CHAIN_ID_DEC)"
    else
        _fail "L1 chainId 불일치: 실제=$L1_CHAIN_ID_DEC, 기대=$PARENT_CHAIN_ID"
    fi
fi

# ---------------------------------------------------------------
# [L1] Depositor 잔액
# ---------------------------------------------------------------
echo ""
echo "--- L1 depositor 잔액 ---"
if [ -n "${L2_DEPOSITOR_ADDRESS:-}" ]; then
    L1_BAL_HEX=$(_rpc "$PARENT_CHAIN_RPC" \
        "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$L2_DEPOSITOR_ADDRESS\",\"latest\"],\"id\":1}" \
        | jq -r '.result // empty' 2>/dev/null || echo "")
    L1_BAL_HEX="${L1_BAL_HEX:-0x0}"
    _info "L1 depositor ($L2_DEPOSITOR_ADDRESS): $(format_wei_eth "$L1_BAL_HEX")"
    if hex_is_zero "$L1_BAL_HEX"; then
        _warn "L1 depositor 잔액 0  (deposit 후 정상 — 전액 L2로 이동)"
    else
        _ok "L1 depositor 잔액 있음"
    fi
fi

# ---------------------------------------------------------------
# [L1] Contracts code
# ---------------------------------------------------------------
echo ""
echo "--- L1 contracts ---"
ROLLUP_ADDR="" BRIDGE_ADDR="" INBOX_ADDR="" OUTBOX_ADDR="" SEQ_INBOX_ADDR=""
if [ -f "$PROJECT_DIR/artifacts/deployment.json" ]; then
    ROLLUP_ADDR=$(jq -r '.rollup        // empty' "$PROJECT_DIR/artifacts/deployment.json" 2>/dev/null || echo "")
    BRIDGE_ADDR=$(jq -r '.bridge        // empty' "$PROJECT_DIR/artifacts/deployment.json" 2>/dev/null || echo "")
    INBOX_ADDR=$(jq -r  '.inbox         // empty' "$PROJECT_DIR/artifacts/deployment.json" 2>/dev/null || echo "")
    OUTBOX_ADDR=$(jq -r '.outbox        // empty' "$PROJECT_DIR/artifacts/deployment.json" 2>/dev/null || echo "")
    SEQ_INBOX_ADDR=$(jq -r '.sequencerInbox // empty' "$PROJECT_DIR/artifacts/deployment.json" 2>/dev/null || echo "")

    check_contract_code "rollup"         "$ROLLUP_ADDR"    "$PARENT_CHAIN_RPC"
    check_contract_code "bridge"         "$BRIDGE_ADDR"    "$PARENT_CHAIN_RPC"
    check_contract_code "inbox"          "$INBOX_ADDR"     "$PARENT_CHAIN_RPC"
    check_contract_code "outbox"         "$OUTBOX_ADDR"    "$PARENT_CHAIN_RPC"
    check_contract_code "sequencerInbox" "$SEQ_INBOX_ADDR" "$PARENT_CHAIN_RPC"
else
    _warn "artifacts/deployment.json 없음 — contract 검증 건너뜀"
fi

# ---------------------------------------------------------------
# [L1] Batch posting 이벤트 (start 이후)
# ---------------------------------------------------------------
echo ""
echo "--- L1 batch posting (fromBlock=$L1_FROM_HEX) ---"
if [ -n "${SEQ_INBOX_ADDR:-}" ] && [ "$SEQ_INBOX_ADDR" != "null" ]; then
    LOG_RESP=$(_rpc "$PARENT_CHAIN_RPC" \
        "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"$SEQ_INBOX_ADDR\",\"fromBlock\":\"$L1_FROM_HEX\",\"toBlock\":\"latest\"}],\"id\":1}")
    LOG_COUNT=$(echo "$LOG_RESP" | jq '.result | length' 2>/dev/null || echo 0)
    if [ "${LOG_COUNT:-0}" -gt 0 ]; then
        _ok "sequencerInbox 이벤트 ${LOG_COUNT}개 (batch posting 동작 중)"
    else
        _warn "sequencerInbox 이벤트 없음 (start 이후 $L1_FROM_HEX~latest) — 시간 더 필요할 수 있음"
    fi
else
    _warn "sequencerInbox 주소 없음 — batch posting 검증 건너뜀"
fi

# ---------------------------------------------------------------
# [L1] Assertion 이벤트 (start 이후)
# ---------------------------------------------------------------
echo ""
echo "--- L1 assertion (fromBlock=$L1_FROM_HEX) ---"
if [ -n "${ROLLUP_ADDR:-}" ] && [ "$ROLLUP_ADDR" != "null" ]; then
    LOG_RESP=$(_rpc "$PARENT_CHAIN_RPC" \
        "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"$ROLLUP_ADDR\",\"fromBlock\":\"$L1_FROM_HEX\",\"toBlock\":\"latest\"}],\"id\":1}")
    LOG_COUNT=$(echo "$LOG_RESP" | jq '.result | length' 2>/dev/null || echo 0)
    if [ "${LOG_COUNT:-0}" -gt 0 ]; then
        _ok "rollup 이벤트 ${LOG_COUNT}개 (assertion 동작 중)"
    else
        _warn "rollup 이벤트 없음 (start 이후 $L1_FROM_HEX~latest) — staker assertion 미확인 (시간 더 필요)"
    fi
else
    _warn "rollup 주소 없음 — assertion 검증 건너뜀"
fi

# ---------------------------------------------------------------
# [L2] RPC 연결 및 chainId
# ---------------------------------------------------------------
echo ""
echo "=== [L2] ==="
echo ""
echo "--- L2 RPC 연결 ---"
L2_RESP=$(_rpc "$L2_RPC" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
L2_CHAIN_ID_HEX=$(echo "$L2_RESP" | jq -r '.result // empty' 2>/dev/null || echo "")
if [ -z "$L2_CHAIN_ID_HEX" ]; then
    _fail "L2 RPC ($L2_RPC) 응답 없음 — pnpm run start 필요"
else
    L2_CHAIN_ID_DEC=$(hex_to_dec "$L2_CHAIN_ID_HEX")
    EXPECTED="${L2_CHAIN_ID:-}"
    if [ -n "$EXPECTED" ] && [ "$L2_CHAIN_ID_DEC" != "$EXPECTED" ]; then
        _fail "L2 chainId 불일치: 실제=$L2_CHAIN_ID_DEC, 기대=$EXPECTED"
    else
        _ok "L2 RPC 응답 (chainId=$L2_CHAIN_ID_DEC)"
    fi
fi

# ---------------------------------------------------------------
# [L2] 블록 생성 확인
# ---------------------------------------------------------------
echo ""
echo "--- L2 블록 생성 ---"
BN1_HEX=$(_rpc "$L2_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')
BN1=$(hex_to_dec "${BN1_HEX:-0x0}")
_info "현재 블록: $BN1  (6초 대기 중...)"
sleep 6
BN2_HEX=$(_rpc "$L2_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')
BN2=$(hex_to_dec "${BN2_HEX:-0x0}")
if [ "$BN2" -gt "$BN1" ]; then
    _ok "블록 생성 중: $BN1 → $BN2"
else
    _fail "블록 생성 없음: $BN1 → $BN2  (sequencer 상태 이상)"
fi

# ---------------------------------------------------------------
# [L2] 계정 잔액
# ---------------------------------------------------------------
echo ""
echo "--- L2 계정 잔액 ---"
check_l2_balance() {
    local role="$1" addr="${2:-}"
    if [ -z "$addr" ]; then
        _info "$role: 주소 미설정 (건너뜀)"
        return
    fi
    local resp bal_hex
    resp=$(_rpc "$L2_RPC" "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$addr\",\"latest\"],\"id\":1}")
    bal_hex=$(echo "$resp" | jq -r '.result // empty' 2>/dev/null || echo "")
    bal_hex="${bal_hex:-0x0}"
    if hex_is_zero "$bal_hex"; then
        _warn "$role ($addr): 0 wei  (pnpm run distribute 미실행?)"
    else
        _ok "$role ($addr): $(format_wei_eth "$bal_hex")"
    fi
}

check_l2_balance "l2Depositor"  "${L2_DEPOSITOR_ADDRESS:-}"
check_l2_balance "deployer"     "${L2_DEPLOYER_ADDRESS:-}"
check_l2_balance "rollup_owner" "${L2_ROLLUP_OWNER_ADDRESS:-}"
check_l2_balance "sequencer"    "${L2_SEQUENCER_ADDRESS:-}"
check_l2_balance "batch_poster" "${L2_BATCH_POSTER_ADDRESS:-}"
check_l2_balance "validator"    "${L2_VALIDATOR_ADDRESS:-}"
[ -n "${L2_TEST_USER_ADDRESS:-}" ] && check_l2_balance "test_user" "$L2_TEST_USER_ADDRESS"

# ---------------------------------------------------------------
# [L2] Sequencer feed port
# ---------------------------------------------------------------
echo ""
echo "--- Sequencer feed port ---"
if check_port_open "$L2_FEED_PORT_VAL" 2>/dev/null; then
    _ok "feed port ${L2_FEED_PORT_VAL} 열려 있음"
else
    _warn "feed port ${L2_FEED_PORT_VAL} 미응답  (sequencer 초기화 중이거나 feed 비활성화)"
fi

# ---------------------------------------------------------------
# [CONFIG] sequencer_config.json 정책 검증 (FAIL if disabled)
# ---------------------------------------------------------------
echo ""
echo "=== [CONFIG] ==="
echo ""
echo "--- sequencer_config.json 정책 (batch-poster / staker) ---"
SEQ_CONFIG="$PROJECT_DIR/config/sequencer_config.json"
if [ -f "$SEQ_CONFIG" ]; then
    BP_ENABLE=$(jq -r '.node["batch-poster"].enable // false' "$SEQ_CONFIG")
    ST_ENABLE=$(jq -r '.node.staker.enable // false' "$SEQ_CONFIG")
    if [ "$BP_ENABLE" = "true" ]; then
        _ok "node.batch-poster.enable = true"
    else
        _fail "node.batch-poster.enable = $BP_ENABLE  (반드시 true여야 함)"
    fi
    if [ "$ST_ENABLE" = "true" ]; then
        _ok "node.staker.enable = true"
    else
        _fail "node.staker.enable = $ST_ENABLE  (정책 위반 — staker 비활성화 금지)"
    fi
else
    _warn "sequencer_config.json 없음 — 정책 검증 건너뜀"
fi

# ---------------------------------------------------------------
# [DOCKER] sequencer service 상태
# ---------------------------------------------------------------
echo ""
echo "--- Docker service 상태 ---"
cd "$PROJECT_DIR"
SEQ_STATE=$(docker compose ps --format json sequencer 2>/dev/null | \
    jq -r 'if type == "array" then .[0] else . end | .State // .Status // empty' 2>/dev/null || echo "")
if echo "$SEQ_STATE" | grep -qiE "^running"; then
    _ok "sequencer: running"
else
    _warn "sequencer 상태: '${SEQ_STATE:-unknown}'  (docker compose ps 로 직접 확인 권장)"
fi

# ---------------------------------------------------------------
# 결과 요약
# ---------------------------------------------------------------
echo ""
echo "============================================"
if [ "$ERRORS" -eq 0 ]; then
    echo "검증 완료 — 모든 항목 통과."
else
    echo "ERROR: ${ERRORS}개 항목 실패 — 위 내용을 확인하세요."
    exit 1
fi
