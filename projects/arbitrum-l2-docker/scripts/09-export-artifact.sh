#!/usr/bin/env bash
# 09-export-artifact.sh — artifacts/l2-chain-info.json 생성
#
# L3 parent chain 구성에 사용되는 최종 artifact.
# Private key 포함 금지 (생성 후 자동 검증).
#
# 필수 입력 파일:
#   config/l2_chain_info.json         (롤업 주소 등)
#   artifacts/deployment.json         (컨트랙트 주소 fallback)
#   artifacts/fund-l1-accounts.json   (L1 role funding 결과)
#   artifacts/l2-start.json           (sequencer 기동 정보)
#   artifacts/deposit-l1-to-l2.json   (deposit 결과)
#   artifacts/fund-l2-accounts.json   (L2 배분 결과)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project
load_resolved_l1_config

echo "=== 09-export-artifact (arbitrum-l2-docker) ==="
echo ""

# ---------------------------------------------------------------
# 필수 파일 확인
# ---------------------------------------------------------------
echo "--- 필수 파일 확인 ---"
for f in \
    config/l2_chain_info.json \
    artifacts/deployment.json \
    artifacts/fund-l1-accounts.json \
    artifacts/l2-start.json \
    artifacts/deposit-l1-to-l2.json \
    artifacts/fund-l2-accounts.json; do
    if [ ! -f "$PROJECT_DIR/$f" ]; then
        echo "[ERROR] $f 없음"
        echo "        실행 순서: check → load:l1 → fund:l1 → config:chain → deploy → config:node → start → deposit → distribute"
        exit 1
    fi
    _ok "$f"
done

# ---------------------------------------------------------------
# 컨트랙트 주소 추출 (l2_chain_info.json 우선, deployment.json fallback)
# ---------------------------------------------------------------
echo ""
echo "--- 컨트랙트 주소 추출 ---"
L2_INFO="$PROJECT_DIR/config/l2_chain_info.json"
DEPLOY="$PROJECT_DIR/artifacts/deployment.json"

_extract() {
    local jq_l2="$1" jq_dep="$2"
    local val
    val=$(jq -r "$jq_l2" "$L2_INFO" 2>/dev/null || echo "")
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        val=$(jq -r "$jq_dep" "$DEPLOY" 2>/dev/null || echo "")
    fi
    echo "$val"
}

ROLLUP_ADDR=$(_extract '.[0].rollup.rollup          // empty' '.rollup          // empty')
BRIDGE_ADDR=$(_extract '.[0].rollup.bridge          // empty' '.bridge          // empty')
INBOX_ADDR=$(_extract  '.[0].rollup.inbox           // empty' '.inbox           // empty')
OUTBOX_ADDR=$(_extract '.[0].rollup.outbox          // empty' '.outbox          // empty')
SEQ_INBOX_ADDR=$(_extract '.[0].rollup.sequencerInbox    // empty' '.sequencerInbox    // empty')
EVENT_INBOX_ADDR=$(_extract '.[0].rollup.rollupEventInbox // empty' '.rollupEventInbox // empty')

for pair in "rollup:$ROLLUP_ADDR" "bridge:$BRIDGE_ADDR" "inbox:$INBOX_ADDR" "outbox:$OUTBOX_ADDR" "sequencerInbox:$SEQ_INBOX_ADDR"; do
    name="${pair%%:*}"
    val="${pair#*:}"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo "[ERROR] $name 주소 추출 실패"
        echo "        config/l2_chain_info.json 또는 artifacts/deployment.json 확인"
        exit 1
    fi
    _info "  $name = $val"
done
[ -n "${EVENT_INBOX_ADDR:-}" ] && [ "$EVENT_INBOX_ADDR" != "null" ] && _info "  rollupEventInbox = $EVENT_INBOX_ADDR"

_ok "컨트랙트 주소 추출 완료"

# ---------------------------------------------------------------
# l2-chain-info.json 생성
# ---------------------------------------------------------------
echo ""
echo "--- artifacts/l2-chain-info.json 생성 ---"

GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
L2_RPC_URL="http://localhost:${L2_RPC_PORT:-8547}"
L2_WS_URL="ws://localhost:${L2_WS_PORT:-8548}"
FEED_URL="ws://localhost:${L2_FEED_PORT:-9642}"

DEPOSIT_DATA=$(cat "$PROJECT_DIR/artifacts/deposit-l1-to-l2.json")
FUND_L1_DATA=$(jq '.distributions' "$PROJECT_DIR/artifacts/fund-l1-accounts.json")
L2_START_DATA=$(cat "$PROJECT_DIR/artifacts/l2-start.json")
FUND_DATA=$(jq '.distributions' "$PROJECT_DIR/artifacts/fund-l2-accounts.json")

mkdir -p "$PROJECT_DIR/artifacts"

jq -n \
    --argjson chain_id         "${L2_CHAIN_ID:-1721702}" \
    --arg     chain_name       "${L2_CHAIN_NAME:-l2konet-dev}" \
    --argjson parent_chain_id  "$PARENT_CHAIN_ID" \
    --arg     l2_rpc           "$L2_RPC_URL" \
    --arg     l2_ws            "$L2_WS_URL" \
    --arg     feed_url         "$FEED_URL" \
    --arg     rollup           "$ROLLUP_ADDR" \
    --arg     bridge           "$BRIDGE_ADDR" \
    --arg     inbox            "$INBOX_ADDR" \
    --arg     outbox           "$OUTBOX_ADDR" \
    --arg     seq_inbox        "$SEQ_INBOX_ADDR" \
    --arg     event_inbox      "${EVENT_INBOX_ADDR:-}" \
    --arg     l2_depositor     "${L2_DEPOSITOR_ADDRESS:-}" \
    --arg     deployer         "${L2_DEPLOYER_ADDRESS:-}" \
    --arg     rollup_owner     "${L2_ROLLUP_OWNER_ADDRESS:-}" \
    --arg     sequencer        "${L2_SEQUENCER_ADDRESS:-}" \
    --arg     batch_poster     "${L2_BATCH_POSTER_ADDRESS:-}" \
    --arg     validator        "${L2_VALIDATOR_ADDRESS:-}" \
    --arg     test_user        "${L2_TEST_USER_ADDRESS:-}" \
    --arg     parent_rpc       "$PARENT_CHAIN_RPC" \
    --arg     parent_ws        "${PARENT_CHAIN_WS:-}" \
    --arg     native_symbol    "${L2_NATIVE_TOKEN_SYMBOL:-ETH}" \
    --argjson native_decimals  "${L2_NATIVE_TOKEN_DECIMALS:-18}" \
    --arg     custom_gas_token "${L2_CUSTOM_GAS_TOKEN:-false}" \
    --argjson l1_funding       "$FUND_L1_DATA" \
    --argjson l2_start         "$L2_START_DATA" \
    --argjson deposit          "$DEPOSIT_DATA" \
    --argjson funded_accounts  "$FUND_DATA" \
    --arg     generated_at     "$GENERATED_AT" \
    '{
        "chainId": $chain_id,
        "networkId": $chain_id,
        "chainName": $chain_name,
        "parentChainId": $parent_chain_id,
        "parentChainType": "ethereum-pos-devnet",
        "executionRpc": {
            "sequencer": $l2_rpc
        },
        "executionWs": {
            "sequencer": $l2_ws
        },
        "sequencerFeed": {
            "url": $feed_url
        },
        "rollup": {
            "rollup":           $rollup,
            "bridge":           $bridge,
            "inbox":            $inbox,
            "outbox":           $outbox,
            "sequencerInbox":   $seq_inbox,
            "rollupEventInbox": $event_inbox
        },
        "accounts": (
            {
                "l2Depositor": $l2_depositor,
                "deployer":    $deployer,
                "rollupOwner": $rollup_owner,
                "sequencer":   $sequencer,
                "batchPoster": $batch_poster,
                "validator":   $validator
            }
            + if $test_user != "" then {"testUser": $test_user} else {} end
        ),
        "nativeToken": {
            "symbol":          $native_symbol,
            "decimals":        $native_decimals,
            "isCustomGasToken": ($custom_gas_token == "true")
        },
        "parent": {
            "chainId": $parent_chain_id,
            "rpcUrl":  $parent_rpc,
            "wsUrl":   $parent_ws
        },
        "l1Funding":      $l1_funding,
        "l2Start":        $l2_start,
        "deposit":        $deposit,
        "fundedAccounts": $funded_accounts,
        "generatedAt":    $generated_at
    }' > "$PROJECT_DIR/artifacts/l2-chain-info.json"

# Secret field 포함 여부 안전 검증 (private/privkey/mnemonic/secret/password)
if artifact_has_secret_field "$PROJECT_DIR/artifacts/l2-chain-info.json"; then
    echo "[ERROR] l2-chain-info.json에 금지된 secret 필드 감지 — 즉시 삭제"
    rm -f "$PROJECT_DIR/artifacts/l2-chain-info.json"
    exit 1
fi

_ok "artifacts/l2-chain-info.json 생성 완료"
_ok "secret 필드 미포함 확인"

echo ""
_info "chainId    = ${L2_CHAIN_ID:-1721702}"
_info "chainName  = ${L2_CHAIN_NAME:-l2konet-dev}"
_info "L2 RPC     = $L2_RPC_URL"
_info "L2 WS      = $L2_WS_URL"
_info "feed       = $FEED_URL"
_info "rollup     = $ROLLUP_ADDR"
_info "sequencerInbox = $SEQ_INBOX_ADDR"

echo ""
echo "Artifact 생성 완료."
echo "→ artifacts/l2-chain-info.json  (L3 parent chain config용)"
