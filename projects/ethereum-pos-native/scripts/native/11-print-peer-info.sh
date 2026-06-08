#!/usr/bin/env bash
# 11-print-peer-info.sh — 이 노드의 peer 연결 정보 출력
#
# 출력 항목:
#   - Geth enode URL (IPC 소켓 경유)
#   - Prysm beacon ENR, peer_id, p2p_addresses
#
# 사용 목적:
#   이 스크립트의 출력을 상대 노드의 .env에 설정하여 peer 연결을 구성합니다.
#     STATIC_BOOTNODES=<geth enode>
#     STATIC_ENRS=<beacon ENR>
#
# 이후 상대 노드에서:
#   sudo npm run install:services && sudo npm run stop && sudo npm run start
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

NODE_NAME="${NODE_NAME:?'ERROR: NODE_NAME 미설정'}"
EXECUTION_ROOT="${EXECUTION_ROOT:-/var/lib/ethereum-pos-native/geth}"
BEACON_REST_PORT="${BEACON_REST_PORT:-3500}"
IPC_PATH="${EXECUTION_ROOT}/geth.ipc"

# 현재 노드의 호스트 결정 (node0 → NODE0_HOST, node1 → NODE1_HOST)
CURRENT_HOST=""
if [ "$NODE_NAME" = "eth-pos-node0" ]; then
    CURRENT_HOST="${NODE0_HOST:-}"
elif [ "$NODE_NAME" = "eth-pos-node1" ]; then
    CURRENT_HOST="${NODE1_HOST:-}"
fi

echo "========================================"
echo " ${NODE_NAME} peer 연결 정보"
echo "========================================"

# ---------------------------------------------------
echo ""
echo "--- Geth Enode ---"

ENODE=""
if [ -S "$IPC_PATH" ]; then
    ENODE=$(timeout 10 geth attach --exec "admin.nodeInfo.enode" "$IPC_PATH" \
        2>/dev/null | tr -d '"' | head -1 || true)
fi

if [ -n "$ENODE" ]; then
    echo "  raw: $ENODE"

    # IPC에서 반환되는 enode의 IP가 0.0.0.0 또는 127.0.0.1이면 실제 호스트 IP로 교체 필요
    if echo "$ENODE" | grep -qE '@(0\.0\.0\.0|127\.0\.0\.1):'; then
        if [ -n "$CURRENT_HOST" ]; then
            ENODE_FIXED=$(echo "$ENODE" | sed "s|@[^:]*:|@${CURRENT_HOST}:|")
            echo ""
            echo "  *** IP가 loopback — 실제 IP로 교체됨 ***"
            echo "  fixed: $ENODE_FIXED"
        else
            echo ""
            echo "  WARNING: IP가 loopback. .env의 NODE0_HOST 또는 NODE1_HOST를 설정하면 자동 교체됩니다."
            echo "           현재: 교체 불가 (HOST 미설정)"
            ENODE_FIXED="$ENODE"
        fi
    else
        ENODE_FIXED="$ENODE"
    fi

    echo ""
    echo "  [상대 노드 .env에 설정]"
    echo "  STATIC_BOOTNODES=${ENODE_FIXED}"
else
    echo "  [ERROR] enode 조회 실패"
    echo "          IPC 경로: $IPC_PATH"
    if [ ! -S "$IPC_PATH" ]; then
        echo "          IPC 소켓 없음 — Geth 실행 중인지 확인:"
        echo "          systemctl status eth-pos-geth-${NODE_NAME}"
    fi
fi

# ---------------------------------------------------
echo ""
echo "--- Prysm Beacon (ENR / peer_id / p2p_addresses) ---"
BEACON_URL="http://127.0.0.1:${BEACON_REST_PORT}"
IDENTITY_JSON=$(curl -sf "${BEACON_URL}/eth/v1/node/identity" 2>/dev/null || true)

if [ -n "$IDENTITY_JSON" ]; then
    ENR=$(echo "$IDENTITY_JSON"    | jq -r '.data.enr // "N/A"')
    PEER_ID=$(echo "$IDENTITY_JSON" | jq -r '.data.peer_id // "N/A"')
    P2P_ADDRS=$(echo "$IDENTITY_JSON" | jq -r '.data.p2p_addresses[]? // empty' 2>/dev/null || echo "N/A")

    echo "  ENR:    $ENR"
    echo "  peer_id: $PEER_ID"
    echo "  p2p:    $P2P_ADDRS"

    # loopback / unspecified 주소 경고
    _LOOPBACK_WARN=false
    if echo "$P2P_ADDRS" | grep -qE '/(127\.0\.0\.1|0\.0\.0\.0|::1)/'; then
        _LOOPBACK_WARN=true
    fi
    if echo "$ENR" | grep -qE '(127\.0\.0\.1|0\.0\.0\.0)'; then
        _LOOPBACK_WARN=true
    fi
    if [ "$_LOOPBACK_WARN" = "true" ]; then
        echo ""
        echo "  *** WARNING: ENR/p2p_addresses에 loopback 또는 0.0.0.0 주소가 포함되어 있습니다. ***"
        echo "  이 주소로는 외부 인스턴스에서 peer 연결이 실패합니다."
        echo "  해결 방법: .env에 P2P_ADVERTISE_IP=<이 인스턴스의 외부 접근 IP> 설정 후"
        echo "             sudo npm run install:services && sudo npm run stop && sudo npm run start"
    fi

    echo ""
    echo "  [상대 노드 .env에 설정]"
    echo "  STATIC_ENRS=${ENR}"
else
    echo "  [ERROR] beacon REST API 응답 없음: ${BEACON_URL}/eth/v1/node/identity"
    echo "          beacon 실행 중인지 확인:"
    echo "          systemctl status eth-pos-beacon-${NODE_NAME}"
fi

# ---------------------------------------------------
echo ""
echo "========================================"
echo " 상대 노드 설정 절차"
echo "========================================"
echo ""
echo "1. 상대 노드의 .env 편집:"
echo "   NODE0_HOST=<이 노드 IP>  또는  NODE1_HOST=<이 노드 IP>"
if [ -n "${ENODE_FIXED:-}" ]; then
    echo "   STATIC_BOOTNODES=${ENODE_FIXED}"
fi
if [ -n "${ENR:-}" ] && [ "$ENR" != "N/A" ]; then
    echo "   STATIC_ENRS=${ENR}"
fi
echo ""
echo "2. 상대 노드에서 서비스 반영:"
echo "   sudo npm run install:services"
echo "   sudo npm run stop && sudo npm run start"
echo ""
echo "3. peer 연결 확인 (상대 노드):"
echo "   geth attach --exec 'net.peerCount' ${EXECUTION_ROOT}/geth.ipc"
echo "   curl -s http://localhost:${BEACON_REST_PORT}/eth/v1/node/peers | jq '.data | length'"
echo ""
echo "상세: docs/ethereum-pos-native/peer-connection.md"
