#!/usr/bin/env bash
# 03-init-geth.sh — Geth genesis 초기화
# 전제: genesis.json이 $CONFIG_ROOT에 있어야 함 (02-generate-network-config.sh 또는 scp 복사)
# 실행: node0과 node1 각각에서 실행 (동일한 genesis.json 사용)
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
echo "ENV: $ENV_FILE  (NODE_NAME=${NODE_NAME})"

CONFIG_ROOT="${CONFIG_ROOT:-/etc/ethereum-pos-native}"
EXECUTION_ROOT="${EXECUTION_ROOT:-/var/lib/ethereum-pos-native/geth}"
GENESIS_FILE="$CONFIG_ROOT/genesis.json"

# --- 사전 확인 ---
if [ ! -f "$GENESIS_FILE" ]; then
    echo "ERROR: genesis.json 없음: $GENESIS_FILE"
    echo ""
    echo "해결 방법:"
    echo "  node0: npm run generate"
    echo "  node1: scp -r <node0-user>@<node0-host>:${CONFIG_ROOT}/ /etc/"
    exit 1
fi

if [ -d "$EXECUTION_ROOT/geth/chaindata" ]; then
    echo "ERROR: Geth 데이터 디렉토리가 이미 초기화되어 있습니다: $EXECUTION_ROOT/geth/chaindata"
    echo ""
    echo "재초기화가 필요한 경우 (체인 데이터 삭제됩니다):"
    echo "  npm run clean"
    echo "  npm run init"
    exit 1
fi

if ! command -v geth &>/dev/null; then
    echo "ERROR: geth를 찾을 수 없습니다."
    echo "       먼저 실행: npm run install:geth"
    exit 1
fi

# --- 디렉토리 생성 ---
mkdir -p "$EXECUTION_ROOT"

# --- genesis 파일 검증 ---
echo "genesis.json 검증 중..."
CHAIN_ID_IN_GENESIS=$(jq -r '.config.chainId' "$GENESIS_FILE" 2>/dev/null || echo "")
EXPECTED_CHAIN_ID="${CHAIN_ID:-1111}"
if [ "$CHAIN_ID_IN_GENESIS" != "$EXPECTED_CHAIN_ID" ]; then
    echo "WARNING: genesis.json의 chainId($CHAIN_ID_IN_GENESIS)가 env의 CHAIN_ID($EXPECTED_CHAIN_ID)와 다릅니다."
    echo "         genesis.json이 올바른지 확인하세요."
fi
echo "  chainId: $CHAIN_ID_IN_GENESIS"
echo "  genesis hash: $(jq -S . "$GENESIS_FILE" | sha256sum | awk '{print $1}')"

# --- geth init ---
echo ""
echo "Geth 초기화 중..."
echo "  genesis: $GENESIS_FILE"
echo "  datadir: $EXECUTION_ROOT"
geth --datadir="$EXECUTION_ROOT" init "$GENESIS_FILE"

echo ""
echo "Geth 초기화 완료."
echo "  chaindata: $EXECUTION_ROOT/geth/chaindata"

# geth init은 root로 실행되므로 chaindata가 root 소유로 생성됨.
# ethereum 사용자가 이미 존재하면 여기서 소유권 수정.
# 없으면 04-install-systemd-services.sh가 사용자 생성 후 chown -R로 처리.
if id ethereum &>/dev/null 2>&1; then
    chown -R ethereum:ethereum "$EXECUTION_ROOT"
    echo "소유권: $EXECUTION_ROOT → ethereum:ethereum"
else
    echo "NOTE: ethereum 사용자 미존재 — 04-install-systemd-services.sh 실행 시 chown -R 처리됩니다."
fi

echo ""
echo "다음 단계: npm run install:services"
