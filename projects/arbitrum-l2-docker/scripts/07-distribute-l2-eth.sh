#!/usr/bin/env bash
# 07-distribute-l2-eth.sh — L2 ETH 배분 (depositor → role 계정들)
#
# 전제: 06-deposit-eth-to-l2.sh 완료 (L2 depositor에 ETH 있어야 함)
# 동작:
#   - L2_DEPOSITOR_PRIVATE_KEY로 서명, 각 role 계정에 L2 ETH 전송
#   - 이미 충분한 잔액이 있는 계정은 기본 skip
#   - --force: 잔액 무관 강제 전송
#   - artifacts/fund-l2-accounts.json 저장 (private key 미포함)
#
# 사용:
#   pnpm run distribute
#   pnpm run distribute -- --force
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project

echo "=== 07-distribute-l2-eth (arbitrum-l2-docker) ==="
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

if [ ! -f "$PROJECT_DIR/artifacts/deposit-l1-to-l2.json" ]; then
    echo "[ERROR] artifacts/deposit-l1-to-l2.json 없음"
    echo "        먼저 실행: pnpm run deposit"
    exit 1
fi
_ok "deposit artifact 확인"

for var in L2_DEPOSITOR_PRIVATE_KEY L2_DEPOSITOR_ADDRESS; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] $var 미설정 (.env 확인)"
        exit 1
    fi
done
_ok "DEPOSITOR 환경변수 확인"

if [ ! -d "$PROJECT_DIR/node_modules" ]; then
    echo "[ERROR] node_modules 없음 — 먼저 실행: pnpm install"
    exit 1
fi
_ok "node_modules 설치 확인"

# ---------------------------------------------------------------
# L2 RPC 확인
# ---------------------------------------------------------------
echo ""
echo "--- L2 RPC 확인 ---"
L2_RPC="http://localhost:${L2_RPC_PORT:-9545}"
L2_RESP=$(_rpc "$L2_RPC" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
L2_CHAIN_HEX=$(echo "$L2_RESP" | jq -r '.result // empty' 2>/dev/null || echo "")
if [ -z "$L2_CHAIN_HEX" ]; then
    echo "[ERROR] L2 RPC ($L2_RPC) 응답 없음 — 먼저 실행: pnpm run start"
    exit 1
fi
_ok "L2 RPC 응답 확인 (chainId=$(hex_to_dec "$L2_CHAIN_HEX"))"

# ---------------------------------------------------------------
# 배분 대상 목록 빌드 (required/optional 구분)
# ---------------------------------------------------------------
echo ""
echo "--- 배분 대상 계정 ---"
DEPLOYER_FUND="${L2_DEPLOYER_FUND_ETH:-1000}"
OWNER_FUND="${L2_ROLLUP_OWNER_FUND_ETH:-1000}"
SEQ_FUND="${L2_SEQUENCER_FUND_ETH:-1000}"
BATCHER_FUND="${L2_BATCH_POSTER_FUND_ETH:-1000}"
VALIDATOR_FUND="${L2_VALIDATOR_FUND_ETH:-1000}"
TEST_FUND="${L2_TEST_USER_FUND_ETH:-100}"

TARGETS=$(jq -n \
    --arg deployer_addr   "${L2_DEPLOYER_ADDRESS:-}" \
    --arg deployer_amt    "$DEPLOYER_FUND" \
    --arg owner_addr      "${L2_ROLLUP_OWNER_ADDRESS:-}" \
    --arg owner_amt       "$OWNER_FUND" \
    --arg seq_addr        "${L2_SEQUENCER_ADDRESS:-}" \
    --arg seq_amt         "$SEQ_FUND" \
    --arg batcher_addr    "${L2_BATCH_POSTER_ADDRESS:-}" \
    --arg batcher_amt     "$BATCHER_FUND" \
    --arg validator_addr  "${L2_VALIDATOR_ADDRESS:-}" \
    --arg validator_amt   "$VALIDATOR_FUND" \
    --arg testuser_addr   "${L2_TEST_USER_ADDRESS:-}" \
    --arg testuser_amt    "$TEST_FUND" \
    '[
        {"role":"deployer",     "address":$deployer_addr,  "amountEth":$deployer_amt,  "optional":false},
        {"role":"rollup_owner", "address":$owner_addr,     "amountEth":$owner_amt,     "optional":false},
        {"role":"sequencer",    "address":$seq_addr,       "amountEth":$seq_amt,       "optional":false},
        {"role":"batch_poster", "address":$batcher_addr,   "amountEth":$batcher_amt,   "optional":false},
        {"role":"validator",    "address":$validator_addr, "amountEth":$validator_amt, "optional":false},
        {"role":"test_user",    "address":$testuser_addr,  "amountEth":$testuser_amt,  "optional":true}
    ]')

echo "$TARGETS" | jq -r '.[] | "  \(.role) [\(if .optional then "optional" else "required" end)]: \(if .address != "" then .address else "(미설정)" end)  ← \(.amountEth) ETH"'

# ---------------------------------------------------------------
# distribute.js 실행
# ---------------------------------------------------------------
echo ""
echo "--- L2 ETH 배분 실행 ---"
ARTIFACT_PATH="$PROJECT_DIR/artifacts/fund-l2-accounts.json"
mkdir -p "$PROJECT_DIR/artifacts"

cd "$PROJECT_DIR"
L2_RPC="$L2_RPC" \
DEPOSITOR_PRIVATE_KEY="$L2_DEPOSITOR_PRIVATE_KEY" \
DEPOSITOR_ADDRESS="$L2_DEPOSITOR_ADDRESS" \
TARGETS_JSON="$TARGETS" \
ARTIFACT_PATH="$ARTIFACT_PATH" \
FORCE="$FORCE_FLAG" \
    node "$SCRIPT_DIR/js/distribute.js"

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
_ok "artifacts/fund-l2-accounts.json 저장 완료"
echo ""
echo "L2 ETH 배분 완료."
echo "다음 단계: pnpm run verify"
