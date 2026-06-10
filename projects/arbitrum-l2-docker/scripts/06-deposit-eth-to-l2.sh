#!/usr/bin/env bash
# 06-deposit-eth-to-l2.sh — L1 → L2 ETH deposit (Inbox.depositEth)
#
# 전제: 05-start-l2.sh 완료 (L2 RPC 가동 중)
# 동작:
#   1. artifacts/deployment.json에서 inbox 주소 추출
#   2. scripts/js/deposit.js 실행 (ethers.js, L1 tx 전송 + L2 잔액 폴링)
#   3. artifacts/deposit-l1-to-l2.json 저장 (private key 미포함)
#
# L2 genesis prefund 사용 안 함 — L1→L2 deposit만 사용
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project
load_resolved_l1_config

echo "=== 06-deposit-eth-to-l2 (arbitrum-l2-docker) ==="
echo ""

# ---------------------------------------------------------------
# 사전 확인
# ---------------------------------------------------------------
echo "--- 사전 조건 확인 ---"

if [ ! -f "$PROJECT_DIR/artifacts/deployment.json" ]; then
    echo "[ERROR] artifacts/deployment.json 없음"
    echo "        먼저 실행: pnpm run deploy"
    exit 1
fi
_ok "artifacts/deployment.json"

for var in L2_DEPOSITOR_PRIVATE_KEY L2_DEPOSITOR_ADDRESS L1_TO_L2_DEPOSIT_ETH; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] $var 미설정 (.env 확인)"
        exit 1
    fi
done
_ok "환경변수 확인 (DEPOSITOR, DEPOSIT_ETH)"

if [ ! -d "$PROJECT_DIR/node_modules" ]; then
    echo "[ERROR] node_modules 없음 — 먼저 실행: pnpm install"
    exit 1
fi
_ok "node_modules 설치 확인"

# ---------------------------------------------------------------
# Inbox 주소 추출
# ---------------------------------------------------------------
echo ""
echo "--- Inbox 주소 추출 ---"
INBOX_ADDR=$(jq -r '.inbox // empty' "$PROJECT_DIR/artifacts/deployment.json" 2>/dev/null || echo "")
if [ -z "$INBOX_ADDR" ] || [ "$INBOX_ADDR" = "null" ]; then
    echo "[ERROR] artifacts/deployment.json에서 .inbox 추출 실패"
    echo "        배포 결과: $(jq 'keys' "$PROJECT_DIR/artifacts/deployment.json" 2>/dev/null)"
    exit 1
fi
if ! is_valid_address "$INBOX_ADDR"; then
    echo "[ERROR] inbox 주소 형식 오류: $INBOX_ADDR"
    exit 1
fi
_ok "Inbox = $INBOX_ADDR"

# ---------------------------------------------------------------
# L2 RPC 응답 확인
# ---------------------------------------------------------------
echo ""
echo "--- L2 RPC 확인 ---"
L2_RPC="http://localhost:${L2_RPC_PORT:-9545}"
L2_RESP=$(_rpc "$L2_RPC" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
L2_CHAIN_ID_HEX=$(echo "$L2_RESP" | jq -r '.result // empty' 2>/dev/null || echo "")
if [ -z "$L2_CHAIN_ID_HEX" ]; then
    echo "[ERROR] L2 RPC ($L2_RPC) 응답 없음 — 먼저 실행: pnpm run start"
    exit 1
fi
_ok "L2 RPC 응답 (chainId=$(hex_to_dec "$L2_CHAIN_ID_HEX"))"

# ---------------------------------------------------------------
# L1 → L2 deposit 실행
# ---------------------------------------------------------------
echo ""
echo "--- L1 → L2 ETH deposit ---"
_info "L1 RPC   : $PARENT_CHAIN_RPC"
_info "L2 RPC   : $L2_RPC"
_info "Inbox    : $INBOX_ADDR"
_info "Amount   : ${L1_TO_L2_DEPOSIT_ETH} ETH"
_info "From     : $L2_DEPOSITOR_ADDRESS"
echo ""

ARTIFACT_PATH="$PROJECT_DIR/artifacts/deposit-l1-to-l2.json"
mkdir -p "$PROJECT_DIR/artifacts"

cd "$PROJECT_DIR"
L1_RPC="$PARENT_CHAIN_RPC" \
L2_RPC="$L2_RPC" \
INBOX_ADDRESS="$INBOX_ADDR" \
DEPOSITOR_PRIVATE_KEY="$L2_DEPOSITOR_PRIVATE_KEY" \
DEPOSITOR_ADDRESS="$L2_DEPOSITOR_ADDRESS" \
DEPOSIT_AMOUNT_ETH="$L1_TO_L2_DEPOSIT_ETH" \
ARTIFACT_PATH="$ARTIFACT_PATH" \
    node "$SCRIPT_DIR/js/deposit.js"

if [ ! -f "$ARTIFACT_PATH" ]; then
    echo "[ERROR] artifact 생성 실패: $ARTIFACT_PATH"
    exit 1
fi

# Secret field 포함 여부 안전 확인 (private/privkey/mnemonic/secret/password)
if artifact_has_secret_field "$ARTIFACT_PATH"; then
    echo "[ERROR] deposit artifact에 금지된 secret 필드 감지 — 생성 로직 확인 필요"
    exit 1
fi

echo ""
L1_TX=$(jq -r '.l1TxHash' "$ARTIFACT_PATH")
L2_BAL=$(jq -r '.l2BalanceAfterEth' "$ARTIFACT_PATH")
_ok "artifacts/deposit-l1-to-l2.json 저장 완료"
_info "  L1 tx hash      = $L1_TX"
_info "  L2 잔액 (after) = $L2_BAL ETH"

echo ""
echo "L1 → L2 deposit 완료."
echo "다음 단계: pnpm run distribute  (L2 ETH 배분)"
