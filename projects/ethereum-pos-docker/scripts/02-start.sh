#!/usr/bin/env bash
# 02-start.sh — 6개 서비스 기동 (node0 + node1)
# 순서: geth → beacon → validator (compose depends_on으로 관리)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음"; exit 1; }

echo "=== ethereum-pos-docker 시작 ==="
docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    --env-file "$ENV_FILE" \
    up -d \
    geth-node0 beacon-node0 validator-node0 \
    geth-node1 beacon-node1 validator-node1

echo ""
echo "서비스 상태:"
docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    --env-file "$ENV_FILE" \
    ps

echo ""
echo "로그 확인:"
echo "  docker compose logs -f geth-node0"
echo "  docker compose logs -f beacon-node0"
echo ""
echo "peer 연결 (첫 기동 시 필요): pnpm run peer:connect"
echo "finality 검증:               pnpm run verify"
