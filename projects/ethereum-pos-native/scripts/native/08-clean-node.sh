#!/usr/bin/env bash
# 08-clean-node.sh — 노드 체인 데이터 삭제 (복구 불가)
# 삭제 대상: EXECUTION_ROOT, BEACON_ROOT, VALIDATOR_ROOT
# 보존:      CONFIG_ROOT (/etc/ethereum-pos-native) — 공유 네트워크 config
#
# WARNING: 이 스크립트는 모든 체인 데이터를 삭제합니다. 되돌릴 수 없습니다.
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

NODE_NAME="${NODE_NAME:?'ERROR: NODE_NAME 미설정'}"
EXECUTION_ROOT="${EXECUTION_ROOT:-/var/lib/ethereum-pos-native/geth}"
BEACON_ROOT="${BEACON_ROOT:-/var/lib/ethereum-pos-native/prysm-beacon}"
VALIDATOR_ROOT="${VALIDATOR_ROOT:-/var/lib/ethereum-pos-native/prysm-validator}"
CONFIG_ROOT="${CONFIG_ROOT:-/etc/ethereum-pos-native}"

echo ""
echo "========================================================"
echo "  WARNING: 체인 데이터 삭제"
echo "  노드: $NODE_NAME"
echo "========================================================"
echo ""
echo "삭제 예정:"
echo "  $EXECUTION_ROOT"
echo "  $BEACON_ROOT"
echo "  $VALIDATOR_ROOT"
echo ""
echo "보존:"
echo "  $CONFIG_ROOT  (genesis, config, jwtsecret)"
echo ""

# 명시적 확인 요구
echo -n "계속하려면 노드 이름을 입력하세요 (${NODE_NAME}): "
read -r CONFIRM
if [ "$CONFIRM" != "$NODE_NAME" ]; then
    echo "취소됨."
    exit 0
fi

# --- 서비스 정지 ---
echo ""
echo "서비스 정지 중..."
for _svc in "eth-pos-validator-${NODE_NAME}" "eth-pos-beacon-${NODE_NAME}" "eth-pos-geth-${NODE_NAME}"; do
    if systemctl is-active "$_svc" &>/dev/null 2>&1; then
        echo "  정지: $_svc"
        systemctl stop "$_svc" || true
    fi
done
sleep 2

# --- 데이터 삭제 ---
echo ""
echo "데이터 삭제 중..."
for _dir in "$EXECUTION_ROOT" "$BEACON_ROOT" "$VALIDATOR_ROOT"; do
    if [ -d "$_dir" ]; then
        echo "  삭제: $_dir"
        rm -rf "$_dir"
    else
        echo "  없음 (건너뜀): $_dir"
    fi
done

echo ""
echo "=== 삭제 완료 ==="
echo ""
echo "config는 보존됨: $CONFIG_ROOT"
echo "재초기화 절차:"
echo "  1. npm run init"
echo "  2. npm run install:services"
echo "  3. npm run start"
