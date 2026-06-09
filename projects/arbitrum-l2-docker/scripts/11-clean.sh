#!/usr/bin/env bash
# 11-clean.sh — 생성 파일 및 컨테이너 정리
#
# 기본 동작:
#   - docker compose down (컨테이너, 네트워크 삭제)
#   - 생성된 config 파일 삭제 (l1-chain-info.json 제외)
#   - artifacts 삭제 (.gitkeep 제외)
#   - seqdata volume 유지 (체인 데이터 보존)
#
# --volumes 옵션:
#   - seqdata volume도 삭제 (L2 체인 데이터 초기화)
#
# 유지 대상 (어떤 경우에도 삭제 안 함):
#   .env
#   config/l1-chain-info.json
#   config/.gitkeep, artifacts/.gitkeep
#
# 사용:
#   pnpm run clean               # volume 유지
#   pnpm run clean -- --volumes  # volume 포함 전체 초기화
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project

echo "=== 11-clean (arbitrum-l2-docker) ==="
echo ""

REMOVE_VOLUMES=0
for arg in "$@"; do
    case "$arg" in --volumes|-v) REMOVE_VOLUMES=1 ;; esac
done

cd "$PROJECT_DIR"

# ---------------------------------------------------------------
# 컨테이너, 네트워크 정리
# ---------------------------------------------------------------
echo "--- Docker 컨테이너/네트워크 정리 ---"
if [ "$REMOVE_VOLUMES" -eq 1 ]; then
    _warn "--volumes: seqdata volume 삭제 포함 (L2 체인 데이터 초기화됩니다)"
    docker compose down --volumes 2>/dev/null || docker compose down 2>/dev/null || true
    _ok "컨테이너, 네트워크, seqdata volume 삭제됨"
else
    docker compose down 2>/dev/null || true
    _ok "컨테이너, 네트워크 삭제됨"
    _info "seqdata volume 유지  (삭제 포함: pnpm run clean -- --volumes)"
fi

# ---------------------------------------------------------------
# 생성된 config 파일 삭제
# ---------------------------------------------------------------
echo ""
echo "--- 생성된 config 파일 삭제 ---"
CONFIG_FILES=(
    config/l2_chain_config.json
    config/l2_chain_info.json
    config/deployment.json
    config/deployed_chain_info.json
    config/sequencer_config.json
    config/resolved-l1-config.env
    config/val_jwt.hex
)

for f in "${CONFIG_FILES[@]}"; do
    if [ -f "$PROJECT_DIR/$f" ]; then
        rm -f "$PROJECT_DIR/$f"
        _ok "삭제: $f"
    fi
done
_info "유지: config/l1-chain-info.json  (외부 입력 — 수동 삭제: rm config/l1-chain-info.json)"

# ---------------------------------------------------------------
# artifacts 삭제
# ---------------------------------------------------------------
echo ""
echo "--- artifacts 삭제 ---"
ARTIFACT_FILES=(
    artifacts/deployment.json
    artifacts/deployed_chain_info.json
    artifacts/l2-chain-info.json
    artifacts/deposit-l1-to-l2.json
    artifacts/fund-l2-accounts.json
)

for f in "${ARTIFACT_FILES[@]}"; do
    if [ -f "$PROJECT_DIR/$f" ]; then
        rm -f "$PROJECT_DIR/$f"
        _ok "삭제: $f"
    fi
done

echo ""
echo "정리 완료."
if [ "$REMOVE_VOLUMES" -eq 1 ]; then
    echo "전체 초기화됨 — 재시작: pnpm install && pnpm run check && pnpm run load:l1 && ..."
else
    echo "재시작 (체인 데이터 유지): pnpm run check → load:l1 → config:chain → deploy → config:node → start"
fi
