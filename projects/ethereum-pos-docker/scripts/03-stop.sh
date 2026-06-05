#!/usr/bin/env bash
# 03-stop.sh — 서비스 정지 (데이터 보존)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음"; exit 1; }

echo "=== ethereum-pos-docker 정지 ==="
docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    --env-file "$ENV_FILE" \
    stop

echo ""
echo "서비스 상태:"
docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    --env-file "$ENV_FILE" \
    ps

echo ""
echo "재시작: pnpm run start"
