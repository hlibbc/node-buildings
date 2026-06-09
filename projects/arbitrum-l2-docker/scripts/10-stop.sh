#!/usr/bin/env bash
# 10-stop.sh — L2 sequencer 중지 (config/data 유지)
#
# seqdata volume은 삭제하지 않음 — pnpm run start로 재시작 가능
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project

echo "=== 10-stop (arbitrum-l2-docker) ==="
echo ""

cd "$PROJECT_DIR"
_info "sequencer 컨테이너 중지 중..."
docker compose stop sequencer 2>/dev/null || true

_ok "sequencer 중지됨"
_info "seqdata volume 유지 (체인 데이터 보존)"
_info "재시작: pnpm run start"
_info "전체 초기화: pnpm run clean"

echo ""
echo "sequencer 중지 완료."
