#!/usr/bin/env bash
# 04-render-node-configs.sh — sequencer_config.json 생성
#
# 전제: 03-deploy-rollup.sh 완료 (l2_chain_info.json 존재 필요)
#
# single sequencer simple mode 설정:
#   - execution.sequencer.enable = true
#   - node.sequencer = true
#   - node.delayed-sequencer.enable = true
#   - node.batch-poster.enable = true   (L2_BATCH_POSTER_PRIVATE_KEY 필요)
#   - node.staker.enable = true         (고정 — L2_VALIDATOR_PRIVATE_KEY 필수)
#   - node.staker.dangerous.without-block-validator = true
#   - node.dangerous.no-sequencer-coordinator = true
#   - node.batch-poster.redis-url = ""
#
# L2_VALIDATOR_PRIVATE_KEY는 필수입니다.
# staker가 없는 L2는 L3 parent chain으로 불충분합니다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project
load_resolved_l1_config

echo "=== 04-render-node-configs (arbitrum-l2-docker) ==="
echo ""

# ---------------------------------------------------------------
# 사전 파일 확인
# ---------------------------------------------------------------
echo "--- 사전 조건 확인 ---"

L2_CHAIN_INFO="$PROJECT_DIR/config/l2_chain_info.json"
if [ ! -f "$L2_CHAIN_INFO" ]; then
    echo "[ERROR] config/l2_chain_info.json 없음"
    echo "        먼저 실행: pnpm run deploy"
    exit 1
fi
_ok "l2_chain_info.json 존재"

for var in L2_CHAIN_ID L2_BATCH_POSTER_PRIVATE_KEY L2_VALIDATOR_PRIVATE_KEY; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] $var 미설정"
        exit 1
    fi
done
_ok "필수 환경변수 확인 (batch-poster, validator private key 포함)"

# ---------------------------------------------------------------
# batch-poster / validator key → address 검증 및 L1 잔액 확인
# batch-poster와 validator는 L1 트랜잭션을 발생시키므로 L1 ETH 필수
# ---------------------------------------------------------------
echo ""
echo "--- batch-poster / validator L1 준비 확인 ---"

if [ ! -d "$PROJECT_DIR/node_modules" ]; then
    echo "[ERROR] node_modules 없음 — 먼저 실행: pnpm install"
    exit 1
fi

# Batch poster key → address 검증
DERIVED_BP=$(derive_address "$L2_BATCH_POSTER_PRIVATE_KEY")
if [ -z "$DERIVED_BP" ]; then
    echo "[ERROR] L2_BATCH_POSTER_PRIVATE_KEY에서 주소 파생 실패"
    exit 1
fi
EXPECTED_BP=$(printf '%s' "${L2_BATCH_POSTER_ADDRESS:-}" | tr '[:upper:]' '[:lower:]')
if [ -z "$EXPECTED_BP" ]; then
    echo "[ERROR] L2_BATCH_POSTER_ADDRESS 미설정"
    exit 1
fi
if [ "$DERIVED_BP" != "$EXPECTED_BP" ]; then
    echo "[ERROR] L2_BATCH_POSTER_PRIVATE_KEY 주소 불일치"
    echo "  파생된 주소: $DERIVED_BP  설정된 주소: $EXPECTED_BP"
    exit 1
fi
_ok "L2_BATCH_POSTER_PRIVATE_KEY → $DERIVED_BP (주소 일치)"

BP_BAL_HEX=$(_rpc "$PARENT_CHAIN_RPC" \
    "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$L2_BATCH_POSTER_ADDRESS\",\"latest\"],\"id\":1}" \
    | jq -r '.result // empty')
BP_BAL_HEX="${BP_BAL_HEX:-0x0}"
if hex_is_zero "$BP_BAL_HEX"; then
    echo "[ERROR] L2_BATCH_POSTER_ADDRESS ($L2_BATCH_POSTER_ADDRESS) L1 ETH 잔액 없음"
    echo "        batch-poster는 L1 sequencerInbox에 트랜잭션을 발생시킴"
    echo "        먼저 실행: pnpm run fund:l1"
    exit 1
fi
_ok "L2_BATCH_POSTER_ADDRESS L1 잔액: $(format_wei_eth "$BP_BAL_HEX")"

# Validator key → address 검증
DERIVED_VAL=$(derive_address "$L2_VALIDATOR_PRIVATE_KEY")
if [ -z "$DERIVED_VAL" ]; then
    echo "[ERROR] L2_VALIDATOR_PRIVATE_KEY에서 주소 파생 실패"
    exit 1
fi
EXPECTED_VAL=$(printf '%s' "${L2_VALIDATOR_ADDRESS:-}" | tr '[:upper:]' '[:lower:]')
if [ -z "$EXPECTED_VAL" ]; then
    echo "[ERROR] L2_VALIDATOR_ADDRESS 미설정"
    exit 1
fi
if [ "$DERIVED_VAL" != "$EXPECTED_VAL" ]; then
    echo "[ERROR] L2_VALIDATOR_PRIVATE_KEY 주소 불일치"
    echo "  파생된 주소: $DERIVED_VAL  설정된 주소: $EXPECTED_VAL"
    exit 1
fi
_ok "L2_VALIDATOR_PRIVATE_KEY → $DERIVED_VAL (주소 일치)"

VAL_BAL_HEX=$(_rpc "$PARENT_CHAIN_RPC" \
    "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$L2_VALIDATOR_ADDRESS\",\"latest\"],\"id\":1}" \
    | jq -r '.result // empty')
VAL_BAL_HEX="${VAL_BAL_HEX:-0x0}"
if hex_is_zero "$VAL_BAL_HEX"; then
    echo "[ERROR] L2_VALIDATOR_ADDRESS ($L2_VALIDATOR_ADDRESS) L1 ETH 잔액 없음"
    echo "        staker/validator는 L1 rollup에 assertion을 게시함"
    echo "        먼저 실행: pnpm run fund:l1"
    exit 1
fi
_ok "L2_VALIDATOR_ADDRESS L1 잔액: $(format_wei_eth "$VAL_BAL_HEX")"

# ---------------------------------------------------------------
# sequencer_config.json 생성
# 기준: nitro-testnode/scripts/config.ts writeConfigs() + simple mode 분기
# parent-chain.connection.url: PARENT_CHAIN_WS (WebSocket 필수)
# staker.enable = true 고정 — L3 parent chain 용도로 assertion 필요
# ---------------------------------------------------------------
echo ""
echo "--- sequencer_config.json 생성 ---"

SEQ_CONFIG="$PROJECT_DIR/config/sequencer_config.json"

# Nitro expects private keys WITHOUT the 0x prefix.
# Strip it here; .env originals are not modified.
NITRO_BATCH_POSTER_PRIVATE_KEY="${L2_BATCH_POSTER_PRIVATE_KEY#0x}"
NITRO_VALIDATOR_PRIVATE_KEY="${L2_VALIDATOR_PRIVATE_KEY#0x}"

# Validate: must be exactly 64 lowercase hex chars after stripping
for _varname in NITRO_BATCH_POSTER_PRIVATE_KEY NITRO_VALIDATOR_PRIVATE_KEY; do
    _val="${!_varname}"
    if ! printf '%s' "$_val" | grep -qE '^[0-9a-fA-F]{64}$'; then
        echo "[ERROR] $_varname is not a valid 64-char hex key (got ${#_val} chars)"
        echo "        Check the corresponding L2_*_PRIVATE_KEY in .env"
        exit 1
    fi
done
_ok "batch-poster private key: 64-char hex (0x stripped)"
_ok "validator private key:    64-char hex (0x stripped)"

_info "  PARENT_CHAIN_WS = $PARENT_CHAIN_WS"

jq -n \
    --arg parent_chain_ws "$PARENT_CHAIN_WS" \
    --argjson chain_id "$L2_CHAIN_ID" \
    --arg batch_poster_pk "$NITRO_BATCH_POSTER_PRIVATE_KEY" \
    --arg validator_pk "$NITRO_VALIDATOR_PRIVATE_KEY" \
    '{
        "ensure-rollup-deployment": false,
        "parent-chain": {
            "connection": {
                "url": $parent_chain_ws
            }
        },
        "chain": {
            "id": $chain_id,
            "info-files": ["/config/l2_chain_info.json"]
        },
        "node": {
            "bold": {
                "rpc-block-number": "latest",
                "assertion-posting-interval": "10s",
                "assertion-confirming-interval": "10s",
                "parent-chain-block-time": 1
            },
            "staker": {
                "dangerous": {
                    "without-block-validator": true
                },
                "parent-chain-wallet": {
                    "private-key": $validator_pk
                },
                "disable-challenge": false,
                "enable": true,
                "staker-interval": "10s",
                "make-assertion-interval": "10s",
                "strategy": "MakeNodes",
                "use-smart-contract-wallet": true
            },
            "sequencer": true,
            "dangerous": {
                "no-sequencer-coordinator": true,
                "disable-blob-reader": true
            },
            "delayed-sequencer": {
                "enable": true
            },
            "seq-coordinator": {
                "enable": false,
                "redis-url": ""
            },
            "batch-poster": {
                "enable": true,
                "redis-url": "",
                "max-delay": "30s",
                "l1-block-bound": "ignore",
                "parent-chain-wallet": {
                    "private-key": $batch_poster_pk
                },
                "data-poster": {
                    "wait-for-l1-finality": false
                }
            }
        },
        "execution": {
            "sequencer": {
                "enable": true,
                "expected-surplus-soft-threshold": "-1000000000000000000",
                "expected-surplus-hard-threshold": "-1000000000000000000",
                "dangerous": {
                    "disable-blob-base-fee-check": true
                }
            },
            "forwarding-target": "null"
        },
        "persistent": {
            "chain": "local"
        },
        "ws": {
            "addr": "0.0.0.0"
        },
        "http": {
            "addr": "0.0.0.0",
            "vhosts": "*",
            "corsdomain": "*"
        }
    }' > "$SEQ_CONFIG"

_ok "config/sequencer_config.json 생성 완료"
_info "  parent-chain.connection.url      = $PARENT_CHAIN_WS"
_info "  chain.id                         = $L2_CHAIN_ID"
_info "  execution.sequencer.enable       = true"
_info "  node.sequencer                   = true"
_info "  node.delayed-sequencer.enable    = true"
_info "  node.batch-poster.enable         = true"
_info "  node.staker.enable               = true  (고정)"
_info "  without-block-validator          = true"
_info "  no-sequencer-coordinator         = true"
_info "  batch-poster.redis-url           = ''"

echo ""
echo "Node config 생성 완료."
echo "다음 단계: pnpm run start (L2 sequencer 기동)"
