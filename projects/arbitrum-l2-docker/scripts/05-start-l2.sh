#!/usr/bin/env bash
# 05-start-l2.sh — L2 sequencer 기동 및 동작 확인
#
# 전제: 04-render-node-configs.sh 완료
# 동작:
#   1. sequencer_config.json, l2_chain_info.json, artifacts/deployment.json 존재 확인
#   2. batch-poster.enable = true, staker.enable = true 정책 검증
#   3. L1 block number 기록 (l2-start.json용)
#   4. sequencer 기동 (docker compose up -d sequencer)
#   5. L2 RPC 응답 대기 (최대 120s)
#   6. chainId 검증
#   7. 블록 생성 확인 (최대 60s 재시도, 미증가 시 FAIL)
#   8. artifacts/l2-start.json 저장
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project
load_resolved_l1_config

echo "=== 05-start-l2 (arbitrum-l2-docker) ==="
echo ""

# ---------------------------------------------------------------
# 사전 조건 확인
# ---------------------------------------------------------------
echo "--- 사전 조건 확인 ---"
for f in config/sequencer_config.json config/l2_chain_info.json artifacts/deployment.json; do
    if [ ! -f "$PROJECT_DIR/$f" ]; then
        echo "[ERROR] $f 없음"
        echo "        먼저 실행: pnpm run config:node"
        exit 1
    fi
    _ok "$f"
done

BATCH_ENABLED=$(jq -r '.node["batch-poster"].enable // false' "$PROJECT_DIR/config/sequencer_config.json")
STAKER_ENABLED=$(jq -r '.node.staker.enable // false' "$PROJECT_DIR/config/sequencer_config.json")

if [ "$BATCH_ENABLED" != "true" ]; then
    echo "[ERROR] sequencer_config.json: node.batch-poster.enable = $BATCH_ENABLED  (must be true)"
    echo "        pnpm run config:node 재실행 필요"
    exit 1
fi
_ok "node.batch-poster.enable = true"

if [ "$STAKER_ENABLED" != "true" ]; then
    echo "[ERROR] sequencer_config.json: node.staker.enable = $STAKER_ENABLED  (must be true — 정책 위반)"
    exit 1
fi
_ok "node.staker.enable = true"

# ---------------------------------------------------------------
# L1 block number 기록 (start 직전)
# ---------------------------------------------------------------
echo ""
echo "--- L1 block 기록 ---"
L1_BN_HEX=$(_rpc "$PARENT_CHAIN_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')
L1_BN_AT_START=$(hex_to_dec "${L1_BN_HEX:-0x0}")
_info "L1 block at start: $L1_BN_AT_START"

# ---------------------------------------------------------------
# sequencer 기동
# ---------------------------------------------------------------
echo ""
echo "--- L2 sequencer 기동 ---"
cd "$PROJECT_DIR"

SEQ_STATE=$(docker compose ps --format json sequencer 2>/dev/null | \
    jq -r 'if type == "array" then .[0] else . end | .State // .Status // empty' 2>/dev/null || echo "")
if echo "$SEQ_STATE" | grep -qiE "^running"; then
    _warn "sequencer 이미 실행 중 (재시작 없이 계속)"
else
    docker compose up -d sequencer
    _ok "docker compose up -d sequencer"
fi

# ---------------------------------------------------------------
# L2 RPC 응답 대기
# ---------------------------------------------------------------
echo ""
echo "--- L2 RPC 응답 대기 (최대 120s) ---"
L2_RPC="http://localhost:${L2_RPC_PORT:-9545}"
_info "L2 RPC: $L2_RPC"

TIMEOUT=120
CHAIN_ID_HEX=""
RPC_WAIT_SECS=0
for i in $(seq 1 $TIMEOUT); do
    RESP=$(_rpc "$L2_RPC" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' || true)
    CHAIN_ID_HEX=$(printf '%s' "$RESP" | jq -r '.result // empty' 2>/dev/null || true)
    if [ -n "$CHAIN_ID_HEX" ]; then
        RPC_WAIT_SECS="$i"
        break
    fi
    if [ $((i % 15)) -eq 0 ]; then
        printf '  %ds 경과...\n' "$i"
    fi
    sleep 1
done

if [ -z "$CHAIN_ID_HEX" ]; then
    echo "[ERROR] L2 RPC 응답 없음 (${TIMEOUT}s timeout)"
    echo "        로그 확인: docker compose logs sequencer"
    exit 1
fi

ACTUAL_CHAIN_ID=$(hex_to_dec "$CHAIN_ID_HEX")
_ok "L2 RPC 응답 확인 (${RPC_WAIT_SECS}s 내)"

# ---------------------------------------------------------------
# Chain ID 검증
# ---------------------------------------------------------------
echo ""
echo "--- Chain ID 검증 ---"
EXPECTED_CHAIN_ID="${L2_CHAIN_ID:-}"
if [ -z "$EXPECTED_CHAIN_ID" ]; then
    _warn "L2_CHAIN_ID 미설정 — 검증 건너뜀 (응답 chainId=$ACTUAL_CHAIN_ID)"
elif [ "$ACTUAL_CHAIN_ID" = "$EXPECTED_CHAIN_ID" ]; then
    _ok "chainId = $ACTUAL_CHAIN_ID (일치)"
else
    echo "[ERROR] chainId 불일치: 실제=$ACTUAL_CHAIN_ID, 기대=$EXPECTED_CHAIN_ID"
    exit 1
fi

# ---------------------------------------------------------------
# 블록 생성 확인 — depositor에서 테스트 tx 전송 후 포함 확인
# Nitro는 empty block을 자동 생성하지 않으므로 tx를 직접 전송합니다.
# ---------------------------------------------------------------
echo ""
echo "--- 블록 생성 확인 (테스트 tx 방식) ---"
BN1_HEX=$(_rpc "$L2_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' || true)
BN1_HEX=$(printf '%s' "$BN1_HEX" | jq -r '.result // empty' 2>/dev/null || true)
BN1=$(hex_to_dec "${BN1_HEX:-0x0}")
_info "기준 블록: $BN1"

BLOCK_STARTED=0
BN2=0

if [ -n "${L2_DEPOSITOR_PRIVATE_KEY:-}" ]; then
    _info "테스트 tx 전송 (depositor → 0xdead, 1 wei) …"
    TX_RESULT=$(node -e "
const { ethers } = require('ethers');
const p = new ethers.JsonRpcProvider('$L2_RPC');
const w = new ethers.Wallet('$L2_DEPOSITOR_PRIVATE_KEY', p);
(async () => {
  try {
    const tx = await w.sendTransaction({ to: '0x000000000000000000000000000000000000dEaD', value: 1n });
    const r = await tx.wait(1, 45000);
    if (!r) { console.log('TIMEOUT'); process.exit(1); }
    console.log('OK:' + r.blockNumber);
  } catch(e) { console.log('ERR:' + e.message.split('\n')[0]); process.exit(1); }
})();
" 2>&1 || true)

    if printf '%s' "$TX_RESULT" | grep -q '^OK:'; then
        BN2=$(printf '%s' "$TX_RESULT" | grep -oE '[0-9]+$')
        BLOCK_STARTED=1
        _ok "블록 생성 확인: $BN1 → $BN2 (테스트 tx 포함)"
    else
        _warn "테스트 tx 실패: $TX_RESULT — polling fallback으로 전환"
    fi
fi

if [ "$BLOCK_STARTED" -eq 0 ]; then
    for i in $(seq 1 60); do
        BN2_HEX=$(_rpc "$L2_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' || true)
        BN2_HEX=$(printf '%s' "$BN2_HEX" | jq -r '.result // empty' 2>/dev/null || true)
        BN2=$(hex_to_dec "${BN2_HEX:-0x0}")
        if [ "$BN2" -gt "$BN1" ]; then
            BLOCK_STARTED=1
            _ok "블록 생성 확인: $BN1 → $BN2 (${i}s 내)"
            break
        fi
        sleep 1
    done
fi

if [ "$BLOCK_STARTED" -eq 0 ]; then
    echo "[ERROR] L2 블록 생성 없음 (tx 전송 실패 + 60s polling timeout)"
    echo "        로그 확인: docker compose logs sequencer"
    echo "        parent chain WS 연결 확인: sequencer_config.json parent-chain.connection.url"
    exit 1
fi

# ---------------------------------------------------------------
# artifacts/l2-start.json 저장
# ---------------------------------------------------------------
echo ""
echo "--- artifacts/l2-start.json 저장 ---"
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$PROJECT_DIR/artifacts"

jq -n \
    --argjson l1_block   "$L1_BN_AT_START" \
    --argjson l2_block   "$BN1" \
    --arg     started_at "$STARTED_AT" \
    --argjson l2_chain_id "${L2_CHAIN_ID:-0}" \
    --argjson parent_chain_id "$PARENT_CHAIN_ID" \
    '{
        "l1BlockAtStart": $l1_block,
        "l2BlockAtStart": $l2_block,
        "startedAt":      $started_at,
        "l2ChainId":      $l2_chain_id,
        "parentChainId":  $parent_chain_id
    }' > "$PROJECT_DIR/artifacts/l2-start.json"

_ok "artifacts/l2-start.json 저장 완료"
_info "  l1BlockAtStart = $L1_BN_AT_START"
_info "  l2BlockAtStart = $BN1"
_info "  startedAt      = $STARTED_AT"

echo ""
echo "L2 sequencer 기동 완료."
echo "다음 단계: pnpm run deposit  (L1 → L2 ETH deposit)"
