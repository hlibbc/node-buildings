#!/usr/bin/env bash
# 05-start-node.sh — 노드 서비스 시작
# 순서: geth → beacon (geth Engine API 준비 후) → validator (beacon 준비 후)
# 주의: force-clear-db 없음 — 정상 재시작 경로에서 데이터 보존
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
GETH_AUTHRPC_PORT="${GETH_AUTHRPC_PORT:-8551}"
BEACON_GRPC_PORT="${BEACON_GRPC_PORT:-4000}"

# --- service 파일 존재 확인 ---
for _svc in "$GETH_SVC" "$BEACON_SVC" "$VALIDATOR_SVC"; do
    if [ ! -f "/etc/systemd/system/${_svc}.service" ]; then
        echo "ERROR: service 파일 없음: /etc/systemd/system/${_svc}.service"
        echo "       먼저 실행: npm run install:services"
        exit 1
    fi
done

_wait_for_port() {
    local host="$1"
    local port="$2"
    local desc="$3"
    local max_wait="${4:-60}"
    local elapsed=0
    echo -n "  $desc 준비 대기 중 (최대 ${max_wait}s)"
    # bash TCP 소켓 확인 (nc 불필요)
    while ! (echo >/dev/tcp/"$host"/"$port") 2>/dev/null; do
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
        if [ "$elapsed" -ge "$max_wait" ]; then
            echo ""
            echo "  TIMEOUT: $desc ($host:$port) — 로그 확인:"
            echo "    journalctl -u eth-pos-geth-${NODE_NAME} --no-pager -n 20"
            return 1
        fi
    done
    echo " OK"
}

echo ""
echo "=== ${NODE_NAME} 시작 ==="

# --- Geth 시작 ---
echo ""
echo "[1/3] Geth 시작..."
systemctl start "$GETH_SVC"
_wait_for_port "127.0.0.1" "$GETH_AUTHRPC_PORT" "Geth authrpc" 60

# --- Beacon 시작 ---
echo ""
echo "[2/3] Prysm beacon-chain 시작..."
systemctl start "$BEACON_SVC"
_wait_for_port "127.0.0.1" "$BEACON_GRPC_PORT" "Prysm gRPC" 90

# --- Validator 시작 ---
echo ""
echo "[3/3] Prysm validator 시작..."
systemctl start "$VALIDATOR_SVC"
sleep 3

# --- 상태 확인 ---
echo ""
echo "=== 서비스 상태 ==="
for _svc in "$GETH_SVC" "$BEACON_SVC" "$VALIDATOR_SVC"; do
    STATUS=$(systemctl is-active "$_svc" 2>/dev/null || echo "unknown")
    echo "  [$STATUS] $_svc"
done

echo ""
echo "로그 확인 명령:"
echo "  journalctl -u $GETH_SVC -f"
echo "  journalctl -u $BEACON_SVC -f"
echo "  journalctl -u $VALIDATOR_SVC -f"
echo ""
echo "finality 검증: npm run verify"
echo ""
echo "TIP: 첫 시작 시 peer가 없으면 finality 달성에 시간이 걸립니다."
echo "     peer 연결 후 2~3 epoch (약 6~10분) 이내에 finalized checkpoint 확인 가능."
echo "     docs/ethereum-pos-native/peer-connection.md 참조"
