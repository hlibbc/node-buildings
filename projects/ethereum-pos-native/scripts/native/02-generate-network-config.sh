#!/usr/bin/env bash
# 02-generate-network-config.sh — 네트워크 공통 config 생성
#
# 실행 위치: node0에서 한 번만 실행
# 생성 파일:
#   $CONFIG_ROOT/jwtsecret
#   $CONFIG_ROOT/genesis.json  (prysmctl이 최종 수정)
#   $CONFIG_ROOT/config.yml
#   $CONFIG_ROOT/genesis.ssz
#
# 주의: 이 스크립트는 절대 node1에서 다시 실행하지 않습니다.
#       node1에는 scp로 /etc/ethereum-pos-native/ 전체를 복사합니다.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"

# --- env 로드 ---
ENV_FILE="$PROJECT_DIR/.env"
for _arg in "$@"; do
    case "$_arg" in --env=*) ENV_FILE="${_arg#*=}"; break ;; esac
done
[ -f "$ENV_FILE" ] || { echo "ERROR: env 파일 없음: $ENV_FILE"; exit 1; }
set -a; source "$ENV_FILE"; set +a
echo "ENV: $ENV_FILE  (NODE_NAME=${NODE_NAME:-<미설정>})"

# --- 변수 설정 ---
CONFIG_ROOT="${CONFIG_ROOT:-/etc/ethereum-pos-native}"
PREFUND_FILE="${PROJECT_DIR}/config/prefund.json"

# --- 중복 실행 방지 ---
if [ -f "$CONFIG_ROOT/genesis.ssz" ]; then
    echo ""
    echo "ERROR: genesis.ssz 이미 존재: $CONFIG_ROOT/genesis.ssz"
    echo "       이 스크립트는 node0에서 한 번만 실행합니다."
    echo "       재생성이 필요한 경우:"
    echo "         sudo rm -rf $CONFIG_ROOT"
    echo "         npm run generate"
    echo ""
    echo "       node1에서 실행한 경우: scp로 node0에서 파일을 복사하세요."
    echo "         scp -r <node0-user>@<node0-host>:$CONFIG_ROOT/ /etc/"
    exit 1
fi

# --- 디렉토리 생성 ---
mkdir -p "$CONFIG_ROOT"
chmod 750 "$CONFIG_ROOT"
echo "Config 디렉토리: $CONFIG_ROOT"

# --- jwtsecret 생성 ---
JWTSECRET_FILE="$CONFIG_ROOT/jwtsecret"
if [ ! -f "$JWTSECRET_FILE" ]; then
    openssl rand -hex 32 | tr -d '\n' > "$JWTSECRET_FILE"
    chmod 640 "$JWTSECRET_FILE"
    echo "jwtsecret 생성: $JWTSECRET_FILE"
else
    echo "jwtsecret 이미 존재: $JWTSECRET_FILE"
fi

# --- genesis.json 생성 ---
GENESIS_FILE="$CONFIG_ROOT/genesis.json"
echo ""
echo "genesis.json 생성 중..."

# prefund.json에서 alloc 구성
ALLOC="{}"
if [ -f "$PREFUND_FILE" ]; then
    echo "  prefund 계정 추가: $PREFUND_FILE"
    ALLOC=$(jq '[.accounts[] | {key: .address, value: {balance: .balance}}] | from_entries' "$PREFUND_FILE" 2>/dev/null || echo "{}")
fi

jq -n \
    --argjson chainId "${CHAIN_ID:-1111}" \
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
            shanghaiTime: 0,
            cancunTime: 0
        },
        nonce: "0x0",
        timestamp: "0x0",
        extraData: "0x",
        gasLimit: "0x1C9C380",
        difficulty: "0x0",
        mixHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
        coinbase: "0x0000000000000000000000000000000000000000",
        alloc: $alloc
    }' > "$GENESIS_FILE"
echo "  genesis.json 작성 완료: $GENESIS_FILE"

# --- config.yml 생성 ---
CONFIG_YML="$CONFIG_ROOT/config.yml"
echo ""
echo "config.yml 생성 중..."
cat > "$CONFIG_YML" << CONFIGEOF
# Ethereum PoS beacon chain config — private devnet
# 생성: $(date -u '+%Y-%m-%dT%H:%M:%SZ')  by 02-generate-network-config.sh
# 직접 수정하지 마세요. 재생성: rm -rf $CONFIG_ROOT && npm run generate

CONFIG_NAME: ${NETWORK_NAME:-eth-pos-devnet}
PRESET_BASE: mainnet

# The Merge: PoS from genesis
TERMINAL_TOTAL_DIFFICULTY: 0
TERMINAL_BLOCK_HASH: 0x0000000000000000000000000000000000000000000000000000000000000000
TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH: 18446744073709551615

# Genesis
MIN_GENESIS_ACTIVE_VALIDATOR_COUNT: ${TOTAL_VALIDATORS:-64}
MIN_GENESIS_TIME: 0
GENESIS_FORK_VERSION: 0x20000089
GENESIS_DELAY: 15

# Fork versions — genesis부터 Deneb 활성화 (all epochs: 0)
ALTAIR_FORK_VERSION:    0x20000090
ALTAIR_FORK_EPOCH:      0
BELLATRIX_FORK_VERSION: 0x20000091
BELLATRIX_FORK_EPOCH:   0
CAPELLA_FORK_VERSION:   0x20000092
CAPELLA_FORK_EPOCH:     0
DENEB_FORK_VERSION:     0x20000093
DENEB_FORK_EPOCH:       0

# Time parameters
SECONDS_PER_SLOT:      ${SECONDS_PER_SLOT:-12}
SLOTS_PER_EPOCH:       ${SLOTS_PER_EPOCH:-32}
SECONDS_PER_ETH1_BLOCK: 12
ETH1_FOLLOW_DISTANCE:  16

# Deposit — interop 모드에서는 실제 deposit 없음 (genesis.ssz에 validator pre-loaded)
DEPOSIT_CHAIN_ID:         ${CHAIN_ID:-1111}
DEPOSIT_NETWORK_ID:       ${NETWORK_ID:-1111}
DEPOSIT_CONTRACT_ADDRESS: 0x0000000000000000000000000000000000000000
CONFIGEOF
echo "  config.yml 작성 완료: $CONFIG_YML"

# --- genesis.ssz 생성 (prysmctl) ---
# NOTE: 이 단계는 실기동 검증이 필요합니다.
# Prysm 최신 stable에서 --fork=deneb 지원 여부를 확인하세요.
# 지원하지 않는 경우:
#   - --fork=capella 또는 --fork=electra 로 변경 시도
#   - config.yml의 DENEB_FORK_EPOCH도 맞게 조정 필요
#   - docs/ethereum-pos-native/version-matrix.md 미검증 항목 참조
echo ""
echo "genesis.ssz 생성 중 (prysmctl)..."
echo "  validators: ${TOTAL_VALIDATORS:-64}개 (interop mode)"
echo "  fork: deneb"
echo "  NOTE: Prysm 최신 stable에서 --fork=deneb 지원 여부는 실기동에서 확인하세요."

if ! command -v prysmctl &>/dev/null; then
    echo "ERROR: prysmctl을 찾을 수 없습니다."
    echo "       먼저 실행: npm run install:prysm"
    exit 1
fi

prysmctl testnet generate-genesis \
    --fork=deneb \
    --num-validators="${TOTAL_VALIDATORS:-64}" \
    --genesis-time-delay=15 \
    --output-ssz="${CONFIG_ROOT}/genesis.ssz" \
    --chain-config-file="${CONFIG_YML}" \
    --geth-genesis-json-in="${GENESIS_FILE}" \
    --geth-genesis-json-out="${GENESIS_FILE}"

echo ""
echo "=== 네트워크 config 생성 완료 ==="
echo "  $CONFIG_ROOT/genesis.json"
echo "  $CONFIG_ROOT/genesis.ssz"
echo "  $CONFIG_ROOT/config.yml"
echo "  $CONFIG_ROOT/jwtsecret"
echo ""
echo "다음 단계:"
echo "  1. [node0] npm run init"
echo "  2. [node0→node1 복사] scp -r ${CONFIG_ROOT}/ <node1-user>@<node1-host>:/etc/"
echo "  3. [node1] npm run install:geth && npm run install:prysm && npm run init"
echo "  자세한 내용: docs/ethereum-pos-native/native-setup.md"
