#!/usr/bin/env bash
# 06-peer-connect.sh — 양쪽 노드 peer 연결 자동화
#
# 처리 순서:
#   1. node0 / node1 Geth enode 조회
#   2. node0 / node1 beacon ENR 조회
#   3. .env 파일의 GETH_NODE*_ENODE, BEACON_NODE*_ENR 업데이트
#   4. beacon 컨테이너 재생성 (--force-recreate) — .env 변경값 반영
#   5. Geth addPeer 동적 추가 (재생성 없이 즉시 적용)
#
# 주의:
#   - docker compose restart 는 기존 컨테이너를 그대로 재시작하므로
#     변경된 .env / environment / command 를 반영하지 않습니다.
#   - BEACON_NODE*_ENR 을 반영하려면 컨테이너 재생성(--force-recreate)이 필요합니다.
#   - Geth peer 는 admin.addPeer(...) 로 즉시 추가되며,
#     .env 의 GETH_NODE*_ENODE 값은 다음 재생성/재기동 시 --bootnodes 로 반영됩니다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: .env 없음"; exit 1; }
set -a; source "$ENV_FILE"; set +a

NODE0_BEACON="http://localhost:${NODE0_BEACON_PORT:-3500}"
NODE1_BEACON="http://localhost:${NODE1_BEACON_PORT:-3600}"

echo "=== peer 연결 설정 ==="
echo ""

# --- genesis 발생 여부 확인 및 자동 리카버리 ---
# peer:connect는 genesis 전에 실행되어야 합니다.
# genesis 후 실행된 경우, Geth에 이미 블록이 있어 beacon이 genesis에서 재시작하면
# forkchoice deadlock이 발생합니다. 이 경우 전체 데이터를 초기화하고 재시작합니다.
NODE0_RPC="http://localhost:${NODE0_RPC_PORT:-8545}"
CURRENT_BLOCK=$(curl -sf -X POST "$NODE0_RPC" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")

if [ "$CURRENT_BLOCK" != "0x0" ] && [ -n "$CURRENT_BLOCK" ]; then
    echo "WARNING: 이미 genesis가 발생했습니다 (blockNumber=$CURRENT_BLOCK)."
    echo "         peer:connect는 genesis 전에 실행되어야 합니다."
    echo ""
    echo "자동 초기화 후 재시작합니다 (볼륨 + Geth 재init)..."
    echo ""

    # 컨테이너 정지 (볼륨은 유지)
    docker compose -f "$PROJECT_DIR/docker-compose.yml" \
        --env-file "$ENV_FILE" \
        down 2>/dev/null || true

    # 체인 데이터 볼륨 삭제 (genesis config는 유지)
    for VOL in geth-node0-data geth-node1-data beacon-node0-data beacon-node1-data \
               validator-node0-data validator-node1-data; do
        FULL_VOL="ethereum-pos-docker_${VOL}"
        docker volume rm "$FULL_VOL" 2>/dev/null && echo "  볼륨 삭제: $FULL_VOL" || true
    done

    # .env의 peer 정보 초기화
    for KEY in GETH_NODE0_ENODE GETH_NODE1_ENODE BEACON_NODE0_ENR BEACON_NODE1_ENR; do
        sed -i.bak "s|^${KEY}=.*|${KEY}=|" "$ENV_FILE" 2>/dev/null || true
    done
    rm -f "$ENV_FILE.bak"

    # Geth 재초기화
    echo ""
    echo "[Geth 재초기화]"
    docker compose -f "$PROJECT_DIR/docker-compose.yml" \
        --env-file "$ENV_FILE" \
        --profile init run --rm geth-init-node0 2>&1 | tail -5
    docker compose -f "$PROJECT_DIR/docker-compose.yml" \
        --env-file "$ENV_FILE" \
        --profile init run --rm geth-init-node1 2>&1 | tail -5

    # 서비스 재기동
    echo ""
    echo "[서비스 재기동]"
    docker compose -f "$PROJECT_DIR/docker-compose.yml" \
        --env-file "$ENV_FILE" \
        up -d

    # beacon 기동 대기
    echo "[beacon 기동 대기 (최대 30s)]..."
    WAITED=0
    while [ $WAITED -lt 30 ]; do
        WAITED=$(( WAITED + 3 ))
        if curl -sf "http://localhost:${NODE0_BEACON_PORT:-3500}/eth/v1/node/health" \
                -o /dev/null 2>/dev/null; then
            echo "  beacon-node0 기동됨 (${WAITED}s)"
            break
        fi
        sleep 3
    done

    # env 재로드
    set -a; source "$ENV_FILE"; set +a

    echo ""
fi

# --- Geth enode 조회 ---
echo "[Geth enode 조회]"
_get_enode() {
    local ctr="$1"
    docker exec "$ctr" geth attach \
        --exec "admin.nodeInfo.enode" /data/geth.ipc 2>/dev/null \
        | tr -d '"' | head -1 || echo ""
}

ENODE0=$(_get_enode "geth-node0")
ENODE1=$(_get_enode "geth-node1")

if [ -z "$ENODE0" ] || [ -z "$ENODE1" ]; then
    echo "ERROR: Geth enode 조회 실패. 컨테이너가 실행 중인지 확인하세요."
    echo "  geth-node0: ${ENODE0:-미조회}"
    echo "  geth-node1: ${ENODE1:-미조회}"
    exit 1
fi

# Docker 내부에서는 컨테이너 이름으로 접근 (loopback IP 교체)
ENODE0=$(echo "$ENODE0" | sed 's|@[^:]*:|@geth-node0:|')
ENODE1=$(echo "$ENODE1" | sed 's|@[^:]*:|@geth-node1:|')
echo "  node0: $ENODE0"
echo "  node1: $ENODE1"

# --- Beacon ENR 조회 ---
echo ""
echo "[Beacon ENR 조회]"
ENR0=$(curl -sf "${NODE0_BEACON}/eth/v1/node/identity" 2>/dev/null \
    | jq -r '.data.enr // ""' || echo "")
ENR1=$(curl -sf "${NODE1_BEACON}/eth/v1/node/identity" 2>/dev/null \
    | jq -r '.data.enr // ""' || echo "")

if [ -z "$ENR0" ] || [ -z "$ENR1" ]; then
    echo "ERROR: beacon ENR 조회 실패."
    echo "  beacon-node0: ${ENR0:-미조회}"
    echo "  beacon-node1: ${ENR1:-미조회}"
    exit 1
fi
echo "  node0 ENR: $ENR0"
echo "  node1 ENR: $ENR1"

# --- .env 업데이트 ---
echo ""
echo "[.env 업데이트]"
_update_env() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i.bak "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >> "$ENV_FILE"
    fi
    echo "  $key 설정됨"
}

_update_env "GETH_NODE0_ENODE" "$ENODE0"
_update_env "GETH_NODE1_ENODE" "$ENODE1"
_update_env "BEACON_NODE0_ENR" "$ENR0"
_update_env "BEACON_NODE1_ENR" "$ENR1"
rm -f "$ENV_FILE.bak"

# .env 재로드: 스크립트 상단에서 소스한 shell 환경(빈 값)이 Docker Compose 변수 치환 시
# --env-file 보다 우선순위가 높으므로, 파일 업데이트 후 반드시 재소스해야 합니다.
set -a; source "$ENV_FILE"; set +a

# --- .env 파일 기록 검증 ---
echo ""
echo "[.env 파일 검증]"
grep -q '^BEACON_NODE0_ENR=enr:' "$ENV_FILE" || { echo "ERROR: BEACON_NODE0_ENR이 .env에 없습니다"; exit 1; }
grep -q '^BEACON_NODE1_ENR=enr:' "$ENV_FILE" || { echo "ERROR: BEACON_NODE1_ENR이 .env에 없습니다"; exit 1; }
grep -q '^GETH_NODE0_ENODE=enode://' "$ENV_FILE" || { echo "ERROR: GETH_NODE0_ENODE가 .env에 없습니다"; exit 1; }
grep -q '^GETH_NODE1_ENODE=enode://' "$ENV_FILE" || { echo "ERROR: GETH_NODE1_ENODE가 .env에 없습니다"; exit 1; }
echo "  BEACON_NODE0_ENR OK"
echo "  BEACON_NODE1_ENR OK"
echo "  GETH_NODE0_ENODE OK"
echo "  GETH_NODE1_ENODE OK"

# --- Geth addPeer (동적 추가, 재시작 불필요) ---
echo ""
echo "[Geth addPeer 적용]"
docker exec geth-node0 geth attach \
    --exec "admin.addPeer(\"${ENODE1}\")" /data/geth.ipc 2>/dev/null || true
docker exec geth-node1 geth attach \
    --exec "admin.addPeer(\"${ENODE0}\")" /data/geth.ipc 2>/dev/null || true
echo "  addPeer 완료"

# --- peer override compose config 검증 ---
echo ""
echo "[peer override compose config 검증]"
if ! docker compose \
        -f "$PROJECT_DIR/docker-compose.yml" \
        -f "$PROJECT_DIR/docker-compose.peer.yml" \
        --env-file "$ENV_FILE" \
        config >/dev/null 2>&1; then
    echo "ERROR: compose config 검증 실패 — .env 내 beacon/geth 설정 확인:"
    grep -n '^BEACON_NODE' "$ENV_FILE" || true
    grep -n '^GETH_NODE' "$ENV_FILE" || true
    exit 1
fi
echo "  compose config 검증 통과"

# --- beacon 재생성 (bootstrap-node 반영) ---
# docker compose restart 는 기존 컨테이너를 재시작할 뿐, .env 변경값을 반영하지 않습니다.
# --force-recreate 로 컨테이너를 재생성해야 BEACON_NODE*_ENR 이 실제로 적용됩니다.
echo ""
echo "[beacon 컨테이너 재생성 (bootstrap-node 반영)]"
docker compose -f "$PROJECT_DIR/docker-compose.yml" \
    -f "$PROJECT_DIR/docker-compose.peer.yml" \
    --env-file "$ENV_FILE" \
    up -d --force-recreate --no-deps beacon-node0 beacon-node1
echo "  beacon-node0, beacon-node1 재생성됨 (BEACON_NODE*_ENR 반영)"

echo ""
echo "=== peer 연결 설정 완료 ==="
echo ""
echo "확인:"
echo "  pnpm run status"
echo "  pnpm run verify -- --allow-waiting"
echo ""
echo "finality 달성까지 약 6~12분 소요 (2 epoch 이상 필요)"
