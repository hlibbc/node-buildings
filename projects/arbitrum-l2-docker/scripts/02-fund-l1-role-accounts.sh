#!/usr/bin/env bash
# 02-fund-l1-role-accounts.sh — L1 ETH 선분배 (depositor → deployer / batchPoster / validator)
#
# 실행 시점: 01-load-l1-config.sh 완료 후, 03-deploy-rollup.sh 전
#
# 배경:
#   - L2 deployer는 L1에 rollup/system contracts를 배포 → L1 ETH 필요
#   - L2 batch-poster는 L1 sequencerInbox에 배치를 게시 → L1 ETH 필요
#   - L2 validator는 L1 rollup에 assertion을 게시 → L1 ETH 필요
#   - 이 세 계정은 L1 genesis에서 직접 prefund받지 않으므로
#     L2_DEPOSITOR가 L1 ETH를 선분배해야 함
#
# 정책:
#   - 이미 충분한 잔액이 있으면 기본적으로 skip
#   - --force: 잔액 무관 강제 재전송
#   - private key artifact 포함 금지
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project
load_resolved_l1_config

echo "=== 02-fund-l1-role-accounts (arbitrum-l2-docker) ==="
echo ""

FORCE_FLAG=0
for arg in "$@"; do
    case "$arg" in --force|-f) FORCE_FLAG=1 ;; esac
done

if [ "$FORCE_FLAG" -eq 1 ]; then
    _warn "--force 활성화: 기존 잔액 무관 재전송"
fi

# ---------------------------------------------------------------
# 사전 확인
# ---------------------------------------------------------------
echo "--- 사전 조건 확인 ---"

for var in L2_DEPOSITOR_PRIVATE_KEY L2_DEPOSITOR_ADDRESS; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] $var 미설정 (.env 확인)"
        exit 1
    fi
done
_ok "DEPOSITOR 환경변수 확인"

for var in L2_DEPLOYER_ADDRESS L2_BATCH_POSTER_ADDRESS L2_VALIDATOR_ADDRESS; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] $var 미설정 (.env 확인)"
        exit 1
    fi
    if ! is_valid_address "${!var}"; then
        echo "[ERROR] $var 잘못된 주소: ${!var}"
        exit 1
    fi
done
_ok "대상 주소 확인 (deployer, batchPoster, validator)"

if [ ! -d "$PROJECT_DIR/node_modules" ]; then
    echo "[ERROR] node_modules 없음 — 먼저 실행: pnpm install"
    exit 1
fi
_ok "node_modules 설치 확인"

# Depositor key → address 검증
echo ""
echo "--- Depositor key 검증 ---"
DERIVED_DEPOSITOR=$(derive_address "$L2_DEPOSITOR_PRIVATE_KEY")
if [ -z "$DERIVED_DEPOSITOR" ]; then
    echo "[ERROR] L2_DEPOSITOR_PRIVATE_KEY에서 주소 파생 실패 — 키 형식 확인"
    exit 1
fi
EXPECTED_DEP=$(printf '%s' "$L2_DEPOSITOR_ADDRESS" | tr '[:upper:]' '[:lower:]')
if [ "$DERIVED_DEPOSITOR" != "$EXPECTED_DEP" ]; then
    echo "[ERROR] L2_DEPOSITOR_PRIVATE_KEY 주소 불일치"
    echo "  파생된 주소: $DERIVED_DEPOSITOR"
    echo "  설정된 주소: $EXPECTED_DEP"
    exit 1
fi
_ok "L2_DEPOSITOR_PRIVATE_KEY → $DERIVED_DEPOSITOR (주소 일치)"

# L1 RPC 확인
echo ""
echo "--- L1 RPC 확인 ---"
L1_CHAIN_RESP=$(_rpc "$PARENT_CHAIN_RPC" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
L1_CHAIN_HEX=$(echo "$L1_CHAIN_RESP" | jq -r '.result // empty' 2>/dev/null || echo "")
if [ -z "$L1_CHAIN_HEX" ]; then
    echo "[ERROR] L1 RPC ($PARENT_CHAIN_RPC) 응답 없음"
    exit 1
fi
_ok "L1 RPC 응답 (chainId=$(hex_to_dec "$L1_CHAIN_HEX"))"

# Depositor L1 잔액 확인
DEP_BAL_HEX=$(_rpc "$PARENT_CHAIN_RPC" \
    "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$L2_DEPOSITOR_ADDRESS\",\"latest\"],\"id\":1}" \
    | jq -r '.result // empty')
DEP_BAL_HEX="${DEP_BAL_HEX:-0x0}"
if hex_is_zero "$DEP_BAL_HEX"; then
    echo "[ERROR] L2_DEPOSITOR_ADDRESS ($L2_DEPOSITOR_ADDRESS) L1 잔액 없음"
    echo "        L1 genesis에서 L2_DEPOSITOR_ADDRESS를 prefund했는지 확인"
    exit 1
fi
_info "  L1 depositor 잔액: $(format_wei_eth "$DEP_BAL_HEX")"
_ok "L1 depositor 잔액 확인"

# ---------------------------------------------------------------
# TARGETS_JSON 빌드
# ---------------------------------------------------------------
echo ""
echo "--- L1 funding 대상 ---"
DEPLOYER_FUND="${L1_DEPLOYER_FUND_ETH:-1000}"
BATCHER_FUND="${L1_BATCH_POSTER_FUND_ETH:-1000}"
VALIDATOR_FUND="${L1_VALIDATOR_FUND_ETH:-1000}"

TARGETS=$(jq -n \
    --arg deployer_addr   "${L2_DEPLOYER_ADDRESS}" \
    --arg deployer_amt    "$DEPLOYER_FUND" \
    --arg batcher_addr    "${L2_BATCH_POSTER_ADDRESS}" \
    --arg batcher_amt     "$BATCHER_FUND" \
    --arg validator_addr  "${L2_VALIDATOR_ADDRESS}" \
    --arg validator_amt   "$VALIDATOR_FUND" \
    '[
        {"role":"deployer",    "address":$deployer_addr,  "amountEth":$deployer_amt,  "optional":false},
        {"role":"batchPoster", "address":$batcher_addr,   "amountEth":$batcher_amt,   "optional":false},
        {"role":"validator",   "address":$validator_addr, "amountEth":$validator_amt, "optional":false}
    ]')

echo "$TARGETS" | jq -r '.[] | "  \(.role): \(.address)  ← \(.amountEth) ETH"'

# ---------------------------------------------------------------
# fund-l1-accounts.js 실행
# ---------------------------------------------------------------
echo ""
echo "--- L1 ETH 선분배 실행 ---"
ARTIFACT_PATH="$PROJECT_DIR/artifacts/fund-l1-accounts.json"
mkdir -p "$PROJECT_DIR/artifacts"

cd "$PROJECT_DIR"
L1_RPC="$PARENT_CHAIN_RPC" \
L2_DEPOSITOR_PRIVATE_KEY="$L2_DEPOSITOR_PRIVATE_KEY" \
L2_DEPOSITOR_ADDRESS="$L2_DEPOSITOR_ADDRESS" \
TARGETS_JSON="$TARGETS" \
ARTIFACT_PATH="$ARTIFACT_PATH" \
FORCE="$FORCE_FLAG" \
    node "$SCRIPT_DIR/js/fund-l1-accounts.js"

if [ ! -f "$ARTIFACT_PATH" ]; then
    echo "[ERROR] artifact 생성 실패: $ARTIFACT_PATH"
    exit 1
fi

# Secret field 포함 여부 안전 확인 (private/privkey/mnemonic/secret/password)
if artifact_has_secret_field "$ARTIFACT_PATH"; then
    echo "[ERROR] artifact에 금지된 secret 필드 감지 (private/mnemonic/secret/password)"
    exit 1
fi

echo ""
_ok "artifacts/fund-l1-accounts.json 저장 완료"
echo ""
echo "L1 ETH 선분배 완료."
echo "다음 단계: pnpm run config:chain  (L2 chain config 생성)"
