#!/usr/bin/env bash
# 06-stop-node.sh — 노드 서비스 정지
# 순서: validator → beacon → geth (역순으로 graceful stop)
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
GETH_SVC="eth-pos-geth-${NODE_NAME}"
BEACON_SVC="eth-pos-beacon-${NODE_NAME}"
VALIDATOR_SVC="eth-pos-validator-${NODE_NAME}"

echo ""
echo "=== ${NODE_NAME} 정지 ==="

_stop_svc() {
    local svc="$1"
    if systemctl is-active "$svc" &>/dev/null; then
        echo "  정지: $svc"
        systemctl stop "$svc"
    else
        echo "  이미 정지됨: $svc"
    fi
}

_stop_svc "$VALIDATOR_SVC"
_stop_svc "$BEACON_SVC"
_stop_svc "$GETH_SVC"

echo ""
echo "=== 정지 완료 ==="
for _svc in "$GETH_SVC" "$BEACON_SVC" "$VALIDATOR_SVC"; do
    STATUS=$(systemctl is-active "$_svc" 2>/dev/null || echo "inactive")
    echo "  [$STATUS] $_svc"
done
echo ""
echo "재시작: npm run start"
