#!/usr/bin/env bash
# 02-render-chain-config.sh — L2 chain config 생성 (l2_chain_config.json)
# rollupcreator의 입력 파일. 03-deploy-rollup.sh 전에 실행해야 한다.
# L2 genesis prefund 없음. alloc 필드 사용 금지.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project

echo "=== 02-render-chain-config (arbitrum-l2-docker) ==="
echo ""

# ---------------------------------------------------------------
# 입력 검증
# ---------------------------------------------------------------
echo "--- 입력 확인 ---"

L2_CHAIN_ID="${L2_CHAIN_ID:-}"
if [ -z "$L2_CHAIN_ID" ]; then
    echo "[ERROR] L2_CHAIN_ID 미설정"
    exit 1
fi
_ok "L2_CHAIN_ID = $L2_CHAIN_ID"

L2_ROLLUP_OWNER_ADDRESS="${L2_ROLLUP_OWNER_ADDRESS:-}"
if [ -z "$L2_ROLLUP_OWNER_ADDRESS" ]; then
    echo "[ERROR] L2_ROLLUP_OWNER_ADDRESS 미설정"
    exit 1
fi
if ! is_valid_address "$L2_ROLLUP_OWNER_ADDRESS"; then
    echo "[ERROR] L2_ROLLUP_OWNER_ADDRESS 형식 오류: $L2_ROLLUP_OWNER_ADDRESS"
    exit 1
fi
_ok "L2_ROLLUP_OWNER_ADDRESS = $L2_ROLLUP_OWNER_ADDRESS"

OUT_FILE="$PROJECT_DIR/config/l2_chain_config.json"

# ---------------------------------------------------------------
# l2_chain_config.json 생성
# 기준: nitro-testnode/scripts/config.ts writeL2ChainConfig()
# - 모든 EVM fork block = 0
# - DataAvailabilityCommittee = false (AnyTrust 미사용)
# - InitialArbOSVersion = 40 (txfiltering 미사용)
# - alloc 필드 없음 (L2 genesis prefund 금지)
# ---------------------------------------------------------------
echo ""
echo "--- l2_chain_config.json 생성 ---"

jq -n \
    --argjson chain_id "$L2_CHAIN_ID" \
    --arg chain_owner "$L2_ROLLUP_OWNER_ADDRESS" \
    '{
        "chainId": $chain_id,
        "homesteadBlock": 0,
        "daoForkSupport": true,
        "eip150Block": 0,
        "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "eip155Block": 0,
        "eip158Block": 0,
        "byzantiumBlock": 0,
        "constantinopleBlock": 0,
        "petersburgBlock": 0,
        "istanbulBlock": 0,
        "muirGlacierBlock": 0,
        "berlinBlock": 0,
        "londonBlock": 0,
        "clique": {
            "period": 0,
            "epoch": 0
        },
        "arbitrum": {
            "EnableArbOS": true,
            "AllowDebugPrecompiles": true,
            "DataAvailabilityCommittee": false,
            "InitialArbOSVersion": 40,
            "InitialChainOwner": $chain_owner,
            "GenesisBlockNum": 0
        }
    }' > "$OUT_FILE"

# alloc 필드가 포함되지 않았는지 안전 확인
if jq -e '.alloc' "$OUT_FILE" &>/dev/null; then
    echo "[ERROR] l2_chain_config.json에 alloc 필드가 생성됨 — L2 genesis prefund 금지"
    rm -f "$OUT_FILE"
    exit 1
fi

_ok "config/l2_chain_config.json 생성 완료"
_info "  chainId   = $L2_CHAIN_ID"
_info "  owner     = $L2_ROLLUP_OWNER_ADDRESS"
_info "  ArbOS     = 40"
_info "  alloc     = 없음 (L2 genesis prefund 금지)"

echo ""
echo "L2 chain config 생성 완료."
echo "다음 단계: pnpm run deploy (롤업 컨트랙트 배포)"
