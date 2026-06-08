#!/usr/bin/env bash
# 05-peer-info.sh — node0 / node1 peer 정보 출력
# 출력 결과를 .env의 GETH_NODE0_ENODE, GETH_NODE1_ENODE, BEACON_NODE0_ENR, BEACON_NODE1_ENR 에 설정
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음"; exit 1; }
set -a; source "$ENV_FILE"; set +a

NODE0_BEACON="http://localhost:${NODE0_BEACON_PORT:-3500}"
NODE1_BEACON="http://localhost:${NODE1_BEACON_PORT:-3600}"

echo "========================================"
echo " peer 연결 정보"
echo "========================================"

for NODE in node0 node1; do
    echo ""
    echo "--- $NODE ---"
    GETH_CTR="geth-${NODE}"
    BEACON_URL="$NODE0_BEACON"
    [ "$NODE" = "node1" ] && BEACON_URL="$NODE1_BEACON"

    # Geth enode (IPC via docker exec)
    echo "[Geth enode]"
    if docker ps --filter "name=^${GETH_CTR}$" --filter "status=running" -q | grep -q .; then
        ENODE=$(docker exec "$GETH_CTR" geth attach \
            --exec "admin.nodeInfo.enode" /data/geth.ipc 2>/dev/null \
            | tr -d '"' | head -1 || echo "")
        if [ -n "$ENODE" ]; then
            echo "  $ENODE"
            # Docker 내부 IP 경고
            if echo "$ENODE" | grep -qE '@(127\.0\.0\.1|0\.0\.0\.0):'; then
                echo "  WARNING: loopback IP — 컨테이너 내부 주소입니다."
                echo "           Docker 내부에서는 컨테이너 이름으로 접근합니다:"
                echo "           enode://$(echo "$ENODE" | sed 's/enode:\/\///' | cut -d@ -f1)@${GETH_CTR}:30303"
            fi
        else
            echo "  조회 실패 — 컨테이너 실행 중인지 확인"
        fi
    else
        echo "  ${GETH_CTR} 미실행"
    fi

    # Beacon ENR / peer_id
    echo "[Beacon ENR]"
    IDENTITY=$(curl -sf "${BEACON_URL}/eth/v1/node/identity" 2>/dev/null || echo "")
    if [ -n "$IDENTITY" ]; then
        ENR=$(echo "$IDENTITY" | jq -r '.data.enr // "N/A"')
        PEER_ID=$(echo "$IDENTITY" | jq -r '.data.peer_id // "N/A"')
        P2P=$(echo "$IDENTITY" | jq -r '.data.p2p_addresses[0] // "N/A"' 2>/dev/null)
        echo "  ENR:     $ENR"
        echo "  peer_id: $PEER_ID"
        echo "  p2p:     $P2P"
    else
        echo "  조회 실패 ($BEACON_URL)"
    fi
done

echo ""
echo "========================================"
echo " .env 업데이트 절차"
echo "========================================"
echo ""
echo "위 정보를 .env 에 설정한 후 pnpm run peer:connect 를 실행하세요."
echo ""
echo "  GETH_NODE0_ENODE=enode://<pubkey>@geth-node0:30303"
echo "  GETH_NODE1_ENODE=enode://<pubkey>@geth-node1:30303"
echo "  BEACON_NODE0_ENR=enr:-..."
echo "  BEACON_NODE1_ENR=enr:-..."
echo ""
echo "자동 처리: pnpm run peer:connect"
