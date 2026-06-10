#!/usr/bin/env bash
# 03-deploy-rollup.sh — L1에 Arbitrum rollup/system contracts 배포
#
# 순서:
#   1. l2_chain_config.json 존재 확인 (02-render-chain-config.sh 선행 필요)
#   2. resolved-l1-config.env 로드 (01-load-l1-config.sh 선행 필요)
#   3. nitro-node 임시 컨테이너로 WASM_MODULE_ROOT 추출
#      (실제 sequencer 서비스 start가 아님 — run --rm 임시 실행)
#   4. rollupcreator create-rollup-testnode 실행
#   5. deployed_chain_info.json → l2_chain_info.json 변환
#   6. deployment.json, deployed_chain_info.json → artifacts/ 복사
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project
load_resolved_l1_config

echo "=== 03-deploy-rollup (arbitrum-l2-docker) ==="
echo ""

# ---------------------------------------------------------------
# 사전 파일 확인
# ---------------------------------------------------------------
echo "--- 사전 조건 확인 ---"

CHAIN_CONFIG="$PROJECT_DIR/config/l2_chain_config.json"
if [ ! -f "$CHAIN_CONFIG" ]; then
    echo "[ERROR] config/l2_chain_config.json 없음"
    echo "        먼저 실행: pnpm run config:chain"
    exit 1
fi
_ok "l2_chain_config.json 존재"

# alloc 필드 재확인 (안전장치)
if jq -e '.alloc' "$CHAIN_CONFIG" &>/dev/null; then
    echo "[ERROR] l2_chain_config.json에 alloc 필드 감지 — L2 genesis prefund 금지"
    exit 1
fi

# 필수 환경 변수 확인
for var in L2_DEPLOYER_PRIVATE_KEY L2_ROLLUP_OWNER_ADDRESS L2_BATCH_POSTER_ADDRESS L2_CHAIN_NAME; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] $var 미설정"
        exit 1
    fi
done
_ok "필수 환경변수 확인"
_info "  PARENT_CHAIN_ID  = $PARENT_CHAIN_ID"
_info "  PARENT_CHAIN_RPC = $PARENT_CHAIN_RPC"

# ---------------------------------------------------------------
# L2_DEPLOYER key → address 검증 및 L1 잔액 확인
# ---------------------------------------------------------------
echo ""
echo "--- L2 Deployer L1 준비 확인 ---"

if [ ! -d "$PROJECT_DIR/node_modules" ]; then
    echo "[ERROR] node_modules 없음 — 먼저 실행: pnpm install"
    exit 1
fi

DERIVED_DEPLOYER=$(derive_address "$L2_DEPLOYER_PRIVATE_KEY")
if [ -z "$DERIVED_DEPLOYER" ]; then
    echo "[ERROR] L2_DEPLOYER_PRIVATE_KEY에서 주소 파생 실패 — 키 형식 확인"
    exit 1
fi
EXPECTED_DEP=$(printf '%s' "$L2_DEPLOYER_ADDRESS" | tr '[:upper:]' '[:lower:]')
if [ "$DERIVED_DEPLOYER" != "$EXPECTED_DEP" ]; then
    echo "[ERROR] L2_DEPLOYER_PRIVATE_KEY 주소 불일치"
    echo "  파생된 주소: $DERIVED_DEPLOYER"
    echo "  설정된 주소: $EXPECTED_DEP"
    exit 1
fi
_ok "L2_DEPLOYER_PRIVATE_KEY → $DERIVED_DEPLOYER (주소 일치)"

DEPLOYER_L1_BAL_HEX=$(_rpc "$PARENT_CHAIN_RPC" \
    "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$L2_DEPLOYER_ADDRESS\",\"latest\"],\"id\":1}" \
    | jq -r '.result // empty')
DEPLOYER_L1_BAL_HEX="${DEPLOYER_L1_BAL_HEX:-0x0}"
if hex_is_zero "$DEPLOYER_L1_BAL_HEX"; then
    echo "[ERROR] L2_DEPLOYER_ADDRESS ($L2_DEPLOYER_ADDRESS) L1 ETH 잔액 없음"
    echo "        먼저 실행: pnpm run fund:l1"
    exit 1
fi
_ok "L2_DEPLOYER_ADDRESS L1 잔액: $(format_wei_eth "$DEPLOYER_L1_BAL_HEX")"

# ---------------------------------------------------------------
# WASM_MODULE_ROOT 추출
# 실제 sequencer 서비스 start가 아닌 run --rm 임시 컨테이너로 파일 읽기
# ---------------------------------------------------------------
echo ""
echo "--- WASM_MODULE_ROOT 추출 ---"
_info "nitro-node 이미지에서 임시 컨테이너 실행 중..."
_info "(sequencer 서비스 start와 무관한 일회성 읽기)"

cd "$PROJECT_DIR"
WASM_MODULE_ROOT=$(docker compose run --rm --entrypoint sh sequencer \
    -c "cat /home/user/target/machines/latest/module-root.txt" 2>/dev/null \
    | tr -d '\r\n')

if [ -z "$WASM_MODULE_ROOT" ]; then
    echo "[ERROR] WASM_MODULE_ROOT 추출 실패"
    echo "        이미지가 없으면 먼저 pull: docker pull \${NITRO_NODE_IMAGE}"
    exit 1
fi
_ok "WASM_MODULE_ROOT = $WASM_MODULE_ROOT"

# ---------------------------------------------------------------
# L1 RPC 사전 검증 (rollupcreator 컨테이너에서)
# Hardhat 실행 전에 advertised RPC가 컨테이너에서도 도달 가능한지 확인합니다.
# ---------------------------------------------------------------
echo ""
echo "--- L1 RPC 사전 검증 (rollupcreator container) ---"
_info "PARENT_CHAIN_RPC = $PARENT_CHAIN_RPC"
_info "rollupcreator 컨테이너에서 eth_chainId 조회 중..."

CHAIN_PROBE_RESULT=$(docker compose run --rm \
    --entrypoint sh rollupcreator \
    -c "curl -sf --connect-timeout 5 --max-time 10 \
        -H 'Content-Type: application/json' \
        -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}' \
        '$PARENT_CHAIN_RPC'" 2>/dev/null || echo "")

if [ -z "$CHAIN_PROBE_RESULT" ]; then
    echo ""
    echo "[ERROR] L1 advertised RPC is not reachable from rollupcreator container."
    echo "        URL: $PARENT_CHAIN_RPC"
    echo ""
    echo "  Check:"
    echo "  1. L1_ADVERTISED_RPC_URL in ethereum-pos-docker .env"
    echo "  2. geth --http.addr=0.0.0.0 (not 127.0.0.1)"
    echo "  3. docker port publish: 8545:8545"
    echo "  4. firewall / network routing between L1 and L2 hosts"
    exit 1
fi

CHAIN_PROBE_HEX=$(printf '%s' "$CHAIN_PROBE_RESULT" | jq -r '.result // empty' 2>/dev/null || echo "")
if [ -z "$CHAIN_PROBE_HEX" ]; then
    echo "[ERROR] eth_chainId 응답 파싱 실패: $CHAIN_PROBE_RESULT"
    exit 1
fi
CHAIN_PROBE_DEC=$(hex_to_dec "$CHAIN_PROBE_HEX")
if [ "$CHAIN_PROBE_DEC" = "$PARENT_CHAIN_ID" ]; then
    _ok "L1 RPC reachable from container (chainId=$CHAIN_PROBE_DEC)"
else
    echo "[ERROR] L1 chainId 불일치: container=$CHAIN_PROBE_DEC, expected=$PARENT_CHAIN_ID"
    exit 1
fi

# ---------------------------------------------------------------
# rollupcreator — rollup/system contracts 배포
# ---------------------------------------------------------------
echo ""
echo "--- rollupcreator 실행 ---"
_info "L1에 Arbitrum rollup/system contracts 배포 중..."
_info "(최초 빌드 시 수 분 소요)"

docker compose run --rm \
    -e PARENT_CHAIN_RPC="$PARENT_CHAIN_RPC" \
    -e DEPLOYER_PRIVKEY="$L2_DEPLOYER_PRIVATE_KEY" \
    -e PARENT_CHAIN_ID="$PARENT_CHAIN_ID" \
    -e CHILD_CHAIN_NAME="$L2_CHAIN_NAME" \
    -e MAX_DATA_SIZE=117964 \
    -e OWNER_ADDRESS="$L2_ROLLUP_OWNER_ADDRESS" \
    -e WASM_MODULE_ROOT="$WASM_MODULE_ROOT" \
    -e SEQUENCER_ADDRESS="$L2_BATCH_POSTER_ADDRESS" \
    -e AUTHORIZE_VALIDATORS=10 \
    -e CHILD_CHAIN_CONFIG_PATH="/config/l2_chain_config.json" \
    -e CHAIN_DEPLOYMENT_INFO="/config/deployment.json" \
    -e CHILD_CHAIN_INFO="/config/deployed_chain_info.json" \
    rollupcreator create-rollup-testnode

_ok "rollupcreator 완료"

# ---------------------------------------------------------------
# 배포 결과 파일 확인
# ---------------------------------------------------------------
echo ""
echo "--- 배포 결과 확인 ---"
for f in deployment.json deployed_chain_info.json; do
    if [ ! -f "$PROJECT_DIR/config/$f" ]; then
        echo "[ERROR] $f 생성 실패"
        exit 1
    fi
    _ok "config/$f 존재"
done

ROLLUP_ADDR=$(jq -r '.[0].rollup.rollup // empty' "$PROJECT_DIR/config/deployed_chain_info.json" 2>/dev/null || echo "")
INBOX_ADDR=$(jq -r '.inbox // empty' "$PROJECT_DIR/config/deployment.json" 2>/dev/null || echo "")
_info "  rollup  = $ROLLUP_ADDR"
_info "  inbox   = $INBOX_ADDR"

# ---------------------------------------------------------------
# deployed_chain_info.json → l2_chain_info.json 변환
# nitro-testnode: jq [.[]] /config/deployed_chain_info.json
# ---------------------------------------------------------------
echo ""
echo "--- l2_chain_info.json 생성 ---"
docker compose run --rm --entrypoint sh rollupcreator \
    -c "jq '[.[]]' /config/deployed_chain_info.json > /config/l2_chain_info.json"

if [ ! -f "$PROJECT_DIR/config/l2_chain_info.json" ]; then
    echo "[ERROR] l2_chain_info.json 변환 실패"
    exit 1
fi
_ok "config/l2_chain_info.json 생성 완료"

# ---------------------------------------------------------------
# artifacts/ 복사
# ---------------------------------------------------------------
echo ""
echo "--- artifacts/ 복사 ---"
cp "$PROJECT_DIR/config/deployment.json"          "$PROJECT_DIR/artifacts/deployment.json"
cp "$PROJECT_DIR/config/deployed_chain_info.json" "$PROJECT_DIR/artifacts/deployed_chain_info.json"
_ok "artifacts/deployment.json"
_ok "artifacts/deployed_chain_info.json"

echo ""
echo "Rollup 배포 완료."
echo "다음 단계: pnpm run config:node (node config 생성)"
