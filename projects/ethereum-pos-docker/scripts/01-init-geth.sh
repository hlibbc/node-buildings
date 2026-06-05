#!/usr/bin/env bash
# 01-init-geth.sh — geth chaindata 초기화 (양쪽 노드)
# 전제: config/genesis.json이 존재해야 함 (00-generate-config.sh 실행 후)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음"; exit 1; }
set -a; source "$ENV_FILE"; set +a

GENESIS_FILE="$PROJECT_DIR/config/genesis.json"
if [ ! -f "$GENESIS_FILE" ]; then
    echo "ERROR: genesis.json 없음: $GENESIS_FILE"
    echo "       먼저 실행: pnpm run generate"
    exit 1
fi

echo "=== Geth 초기화 (node0, node1) ==="
echo "genesis: $GENESIS_FILE"
echo ""

docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    --env-file "$ENV_FILE" \
    --profile init run --rm geth-init-node0

echo ""
docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    --env-file "$ENV_FILE" \
    --profile init run --rm geth-init-node1

echo ""
echo "=== 초기화 완료 ==="
echo "다음 단계: pnpm run start"
