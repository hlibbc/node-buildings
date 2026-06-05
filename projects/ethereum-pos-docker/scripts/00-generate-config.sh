#!/usr/bin/env bash
# 00-generate-config.sh — genesis.json, config.yml, jwtsecret 생성 + prysmctl genesis.ssz 생성
#
# 생성 대상:
#   ./config/jwtsecret     (openssl rand -hex 32)
#   ./config/genesis.json  (jq 템플릿 + 선택적 prefund 적용)
#   ./config/config.yml    (beacon chain 파라미터)
#   ./config/genesis.ssz   (Docker: create-genesis 서비스 실행)
#
# 주의: 한 번만 실행. 재실행 시 genesis.ssz가 이미 있으면 중단됩니다.
#       재생성이 필요한 경우:
#         pnpm run clean  # 볼륨 및 config 삭제
#         pnpm run generate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_DIR/config"
PREFUND_FILE="$CONFIG_DIR/prefund.json"
ENV_FILE="$PROJECT_DIR/.env"

# --- env 로드 ---
[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음 — cp .env.sample .env"; exit 1; }
set -a; source "$ENV_FILE"; set +a
echo "ENV: $ENV_FILE  (CHAIN_ID=${CHAIN_ID:-1111})"

# --- 중복 실행 방지 ---
if [ -f "$CONFIG_DIR/genesis.ssz" ]; then
    echo ""
    echo "ERROR: genesis.ssz 이미 존재: $CONFIG_DIR/genesis.ssz"
    echo "       재생성이 필요하면: pnpm run clean && pnpm run generate"
    exit 1
fi

mkdir -p "$CONFIG_DIR"
echo "Config 디렉토리: $CONFIG_DIR"

# --- jwtsecret ---
JWTSECRET_FILE="$CONFIG_DIR/jwtsecret"
if [ ! -f "$JWTSECRET_FILE" ]; then
    openssl rand -hex 32 | tr -d '\n' > "$JWTSECRET_FILE"
    echo "jwtsecret 생성: $JWTSECRET_FILE"
else
    echo "jwtsecret 이미 존재: $JWTSECRET_FILE"
fi

# --- genesis time 사전 계산 ---
# prysmctl은 genesis.json의 timestamp 필드로 execution genesis block hash를 계산하고
# genesis.ssz의 latest_execution_payload_header.block_hash에 기록합니다.
# Geth도 같은 genesis.json으로 초기화하므로, timestamp가 동일해야 두 hash가 일치합니다.
# generate 실행 시점에 timestamp를 먼저 결정하여 genesis.json과 prysmctl 양쪽에 전달합니다.
GENESIS_TIME=$(( $(date +%s) + 300 ))
GENESIS_TIME_HEX=$(printf '0x%x' "$GENESIS_TIME")
echo "Genesis time: $GENESIS_TIME  ($GENESIS_TIME_HEX)"

# --- genesis.json ---
GENESIS_FILE="$CONFIG_DIR/genesis.json"
echo ""
echo "genesis.json 생성 중..."

ALLOC="{}"
if [ -f "$PREFUND_FILE" ]; then
    echo "  prefund 계정 적용: $PREFUND_FILE"
    ALLOC=$(jq '[.accounts[] | {key: .address, value: {balance: .balance}}] | from_entries' \
        "$PREFUND_FILE" 2>/dev/null || echo "{}")
fi

jq -n \
    --argjson chainId "${CHAIN_ID:-1111}" \
    --argjson genesisTime "$GENESIS_TIME" \
    --arg genesisTimeHex "$GENESIS_TIME_HEX" \
    --argjson alloc "$ALLOC" \
    '{
        config: {
            chainId: $chainId,
            homesteadBlock: 0,
            eip150Block: 0,
            eip155Block: 0,
            eip158Block: 0,
            byzantiumBlock: 0,
            constantinopleBlock: 0,
            petersburgBlock: 0,
            istanbulBlock: 0,
            muirGlacierBlock: 0,
            berlinBlock: 0,
            londonBlock: 0,
            arrowGlacierBlock: 0,
            grayGlacierBlock: 0,
            mergeNetsplitBlock: 0,
            terminalTotalDifficulty: 0,
            terminalTotalDifficultyPassed: true,
            shanghaiTime: $genesisTime,
            cancunTime: $genesisTime
        },
        nonce: "0x0",
        timestamp: $genesisTimeHex,
        extraData: "0x",
        gasLimit: "0x1C9C380",
        difficulty: "0x0",
        mixHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
        coinbase: "0x0000000000000000000000000000000000000000",
        alloc: $alloc
    }' > "$GENESIS_FILE"
echo "  genesis.json 생성 완료: $GENESIS_FILE"

# --- config.yml ---
CONFIG_YML="$CONFIG_DIR/config.yml"
echo ""
echo "config.yml 생성 중..."
cat > "$CONFIG_YML" << CONFIGEOF
# beacon chain config — Docker devnet
# 생성: $(date -u '+%Y-%m-%dT%H:%M:%SZ')  by 00-generate-config.sh
CONFIG_NAME: ${NETWORK_NAME:-eth-pos-devnet}
PRESET_BASE: mainnet

TERMINAL_TOTAL_DIFFICULTY: 0
TERMINAL_BLOCK_HASH: 0x0000000000000000000000000000000000000000000000000000000000000000
TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH: 18446744073709551615

MIN_GENESIS_ACTIVE_VALIDATOR_COUNT: ${TOTAL_VALIDATORS:-64}
MIN_GENESIS_TIME: 0
GENESIS_FORK_VERSION: 0x20000089
GENESIS_DELAY: 15

ALTAIR_FORK_VERSION:    0x20000090
ALTAIR_FORK_EPOCH:      0
BELLATRIX_FORK_VERSION: 0x20000091
BELLATRIX_FORK_EPOCH:   0
CAPELLA_FORK_VERSION:   0x20000092
CAPELLA_FORK_EPOCH:     0
DENEB_FORK_VERSION:     0x20000093
DENEB_FORK_EPOCH:       0
ELECTRA_FORK_VERSION:   0x20000094
ELECTRA_FORK_EPOCH:     18446744073709551615
FULU_FORK_VERSION:      0x20000095
FULU_FORK_EPOCH:        18446744073709551615

SECONDS_PER_SLOT:       ${SECONDS_PER_SLOT:-12}
SLOTS_PER_EPOCH:        ${SLOTS_PER_EPOCH:-32}
SECONDS_PER_ETH1_BLOCK: 12
ETH1_FOLLOW_DISTANCE:   16

DEPOSIT_CHAIN_ID:         ${CHAIN_ID:-1111}
DEPOSIT_NETWORK_ID:       ${NETWORK_ID:-1111}
DEPOSIT_CONTRACT_ADDRESS: 0x0000000000000000000000000000000000000000
CONFIGEOF
echo "  config.yml 생성 완료: $CONFIG_YML"

# --- GENESIS_TIME .env 기록 (docker compose create-genesis 가 읽을 수 있도록) ---
if grep -q '^GENESIS_TIME=' "$ENV_FILE"; then
    sed -i.bak "s|^GENESIS_TIME=.*|GENESIS_TIME=$GENESIS_TIME|" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
else
    printf '\n## Auto-set by pnpm run generate — genesis block timestamp\nGENESIS_TIME=%s\n' "$GENESIS_TIME" >> "$ENV_FILE"
fi
echo "  GENESIS_TIME=$GENESIS_TIME → .env"

# --- genesis.ssz (prysmctl Docker 서비스) ---
echo ""
echo "genesis.ssz 생성 중 (create-genesis 컨테이너)..."
echo "  prysmctl:${PRYSM_VERSION:-?} --fork=deneb --num-validators=${TOTAL_VALIDATORS:-64} --genesis-time=$GENESIS_TIME"
echo ""
echo "NOTE: --fork=deneb 지원 여부는 Prysm 버전에 따라 다릅니다."
echo "      실패 시 docs/ethereum-pos-docker/setup.md 의 troubleshooting 참조"
echo ""

docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    --env-file "$ENV_FILE" \
    --profile init run --rm create-genesis

if [ -f "$CONFIG_DIR/genesis.ssz" ]; then
    echo ""
    echo "=== 생성 완료 ==="
    echo "  $CONFIG_DIR/jwtsecret"
    echo "  $CONFIG_DIR/genesis.json"
    echo "  $CONFIG_DIR/config.yml"
    echo "  $CONFIG_DIR/genesis.ssz"
    echo ""
    echo "다음 단계: pnpm run init"
else
    echo ""
    echo "ERROR: genesis.ssz 생성 실패"
    echo "       docker compose logs 로 create-genesis 컨테이너 로그 확인"
    exit 1
fi
