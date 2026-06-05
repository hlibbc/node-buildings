#!/usr/bin/env bash
# 08-clean.sh — 컨테이너, 볼륨, config 파일 삭제
# WARNING: 모든 체인 데이터가 삭제됩니다. 복구 불가.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
CONFIG_DIR="$PROJECT_DIR/config"

echo "========================================================"
echo "  WARNING: 체인 데이터 및 config 파일 전체 삭제"
echo "  대상: Docker 볼륨 6개 + ./config/ 생성 파일"
echo "========================================================"
echo ""
echo "삭제 대상:"
echo "  볼륨: geth-node0-data, beacon-node0-data, validator-node0-data"
echo "        geth-node1-data, beacon-node1-data, validator-node1-data"
echo "  파일: config/genesis.json, genesis.ssz, config.yml, jwtsecret"
echo ""
echo -n "계속하려면 'yes'를 입력하세요: "
read -r CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "취소됨."; exit 0; }

# 서비스 정지
echo ""
echo "서비스 정지 중..."
if [ -f "$ENV_FILE" ]; then
    docker compose -f "$PROJECT_DIR/docker-compose.yml" \
        --env-file "$ENV_FILE" \
        down --volumes 2>/dev/null || true
else
    docker compose -f "$PROJECT_DIR/docker-compose.yml" \
        down --volumes 2>/dev/null || true
fi

# config 파일 삭제 (예제 파일은 보존)
echo ""
echo "config 파일 삭제 중..."
for F in genesis.json genesis.ssz config.yml jwtsecret; do
    if [ -f "$CONFIG_DIR/$F" ]; then
        rm -f "$CONFIG_DIR/$F"
        echo "  삭제: $CONFIG_DIR/$F"
    fi
done

# .env의 peer 정보 초기화
if [ -f "$ENV_FILE" ]; then
    echo ""
    echo "peer 정보 초기화 중 (.env)..."
    for KEY in GETH_NODE0_ENODE GETH_NODE1_ENODE BEACON_NODE0_ENR BEACON_NODE1_ENR; do
        sed -i.bak "s|^${KEY}=.*|${KEY}=|" "$ENV_FILE" 2>/dev/null || true
    done
    rm -f "$ENV_FILE.bak"
fi

echo ""
echo "=== 삭제 완료 ==="
echo "재시작 절차: pnpm run generate && pnpm run init && pnpm run start"
