#!/usr/bin/env bash
# 00-check-requirements.sh — 실행 전 환경 요구사항 확인
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
init_project

echo "=== check-requirements (arbitrum-l2-docker) ==="
echo ""

# ---------------------------------------------------------------
# 필수 도구
# ---------------------------------------------------------------
check_cmd() {
    local cmd="$1" hint="${2:-}"
    if command -v "$cmd" &>/dev/null; then
        _ok "$cmd"
    else
        _fail "$cmd${hint:+  ($hint)}"
    fi
}

echo "--- 필수 도구 ---"
check_cmd docker       "https://docs.docker.com/engine/install/"
check_cmd jq           "apt install jq / brew install jq"
check_cmd curl
check_cmd node         "https://nodejs.org/"
check_cmd pnpm         "npm install -g pnpm"

echo ""
echo "--- Docker 상태 ---"
if docker info &>/dev/null 2>&1; then
    DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    _ok "Docker daemon 실행 중 (${DOCKER_VER})"
else
    _fail "Docker daemon 미실행"
fi

if docker compose version &>/dev/null 2>&1; then
    COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "unknown")
    _ok "docker compose v${COMPOSE_VER}"
else
    _fail "docker compose 없음 (Docker Desktop 또는 compose plugin 필요)"
fi

# ---------------------------------------------------------------
# .env 파일
# ---------------------------------------------------------------
echo ""
echo "--- .env 파일 ---"
if [ -f "$PROJECT_DIR/.env" ]; then
    _ok ".env 존재"
else
    _fail ".env 없음  →  cp .env.sample .env"
fi

# ---------------------------------------------------------------
# L1 artifact
# ---------------------------------------------------------------
echo ""
echo "--- L1 artifact ---"
L1_INFO_PATH="${L1_CHAIN_INFO_PATH:-$PROJECT_DIR/config/l1-chain-info.json}"
if [ -f "$L1_INFO_PATH" ]; then
    _ok "l1-chain-info.json 존재 ($L1_INFO_PATH)"
else
    _fail "l1-chain-info.json 없음: $L1_INFO_PATH"
    _info "복사: cp ../ethereum-pos-docker/artifacts/l1-chain-info.json ./config/"
fi

# ---------------------------------------------------------------
# 필수 환경 변수
# ---------------------------------------------------------------
echo ""
echo "--- 필수 환경변수 (private key) ---"

check_required_key() {
    local varname="$1"
    local val="${!varname:-}"
    if [ -n "$val" ]; then
        _ok "$varname (set)"
    else
        _fail "$varname 미설정"
    fi
}

check_required_key L2_DEPOSITOR_PRIVATE_KEY
check_required_key L2_DEPLOYER_PRIVATE_KEY
check_required_key L2_ROLLUP_OWNER_PRIVATE_KEY
check_required_key L2_SEQUENCER_PRIVATE_KEY
check_required_key L2_BATCH_POSTER_PRIVATE_KEY
check_required_key L2_VALIDATOR_PRIVATE_KEY

# ---------------------------------------------------------------
# 필수 주소
# ---------------------------------------------------------------
echo ""
echo "--- 필수 주소 ---"

check_required_addr() {
    local varname="$1"
    local val="${!varname:-}"
    if [ -n "$val" ]; then
        if is_valid_address "$val"; then
            _ok "$varname=$val"
        else
            _fail "$varname=$val  (잘못된 주소 형식)"
        fi
    else
        _fail "$varname 미설정"
    fi
}

check_required_addr L2_DEPLOYER_ADDRESS
check_required_addr L2_ROLLUP_OWNER_ADDRESS
check_required_addr L2_SEQUENCER_ADDRESS
check_required_addr L2_BATCH_POSTER_ADDRESS
check_required_addr L2_VALIDATOR_ADDRESS
check_required_addr L2_DEPOSITOR_ADDRESS

echo ""
echo "--- node_modules ---"
if [ -d "$PROJECT_DIR/node_modules" ]; then
    _ok "node_modules 설치됨"
else
    _fail "node_modules 없음  →  pnpm install  (fund:l1/deposit/distribute에서 ethers 사용)"
fi

echo ""
echo "--- L2 체인 설정 ---"
L2_CHAIN_ID="${L2_CHAIN_ID:-}"
if [ -n "$L2_CHAIN_ID" ]; then
    _ok "L2_CHAIN_ID=$L2_CHAIN_ID"
else
    _fail "L2_CHAIN_ID 미설정"
fi

L2_CHAIN_NAME="${L2_CHAIN_NAME:-}"
if [ -n "$L2_CHAIN_NAME" ]; then
    _ok "L2_CHAIN_NAME=$L2_CHAIN_NAME"
else
    _fail "L2_CHAIN_NAME 미설정"
fi

# ---------------------------------------------------------------
# Well-known key 사용 안전성 검사
#
# Anvil well-known dev key는 공개된 키입니다.
# public chain에서 사용하면 자산을 즉시 잃습니다.
#
# 허용 조건: DEVNET_ALLOW_WELL_KNOWN_KEYS=true (devnet 전용 명시 동의)
# 차단 조건: L2_CHAIN_ID 또는 L1_CHAIN_ID가 아래 public chain에 해당
#   1         Ethereum mainnet
#   11155111  Sepolia
#   42161     Arbitrum One
#   421614    Arbitrum Sepolia
# ---------------------------------------------------------------
echo ""
echo "--- Well-known key 안전 검사 ---"

# Anvil well-known private keys (accounts #0–#9)
_ANVIL_KEYS="
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
0x59c6995e998f97a5a0044966f0945382e9dae61377c9d6aefaf11c8f8d7bd4ee
0x5de4111afa1a4b4bc8b6fc3fbb795ccca43dbb99ca0e79e4877e8e19a643c8e
0x7c852118294bb2ba8bbf7e7cc2f2fba4f7442617d9e4a7685e57e72c0c6cde2c
0x47e179ec197488961f6fb3fcb1d04bfb75de443a9a06b5bcb1ce7d089903973
0x8b3a350cf5c34c9194ca3a545d8e2df3544d4f0ef51e0b5de6e787de1400840
0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
0xdbda1821b80551c9d65939329250132c444b3ebff4e91d40fb52eabb9cead4c5
0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
"

# 현재 설정에 well-known key가 있는지 확인
_USING_WELL_KNOWN=0
for _pk_var in L2_DEPOSITOR_PRIVATE_KEY L2_DEPLOYER_PRIVATE_KEY \
               L2_ROLLUP_OWNER_PRIVATE_KEY L2_SEQUENCER_PRIVATE_KEY \
               L2_BATCH_POSTER_PRIVATE_KEY L2_VALIDATOR_PRIVATE_KEY; do
    _pk_val="${!_pk_var:-}"
    [ -z "$_pk_val" ] && continue
    # 대소문자 무시 비교를 위해 소문자로 정규화
    _pk_lc=$(printf '%s' "$_pk_val" | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$_ANVIL_KEYS" | grep -qF "$_pk_lc"; then
        _USING_WELL_KNOWN=1
        break
    fi
done

if [ "$_USING_WELL_KNOWN" -eq 1 ]; then
    # public chain ID 목록
    _PUBLIC_CHAIN_IDS="1 11155111 42161 421614"

    # 검사할 chain ID: L2_CHAIN_ID + L1_CHAIN_ID (설정된 경우)
    _CHAIN_IDS_TO_CHECK="${L2_CHAIN_ID:-}"
    [ -n "${L1_CHAIN_ID:-}" ] && _CHAIN_IDS_TO_CHECK="$_CHAIN_IDS_TO_CHECK ${L1_CHAIN_ID}"

    _ON_PUBLIC_CHAIN=0
    for _cid in $_CHAIN_IDS_TO_CHECK; do
        for _pub in $_PUBLIC_CHAIN_IDS; do
            if [ "$_cid" = "$_pub" ]; then
                _ON_PUBLIC_CHAIN=1
                _fail "CRITICAL: well-known key를 public chain(chainId=$_cid)에서 사용하려 합니다"
                _info "  이 키들은 공개된 anvil dev key입니다 — 자산 즉시 탈취 위험"
                _info "  production/testnet용 새 키를 생성하세요"
                break 2
            fi
        done
    done

    if [ "$_ON_PUBLIC_CHAIN" -eq 0 ]; then
        # devnet이더라도 명시적 동의 필요
        if [ "${DEVNET_ALLOW_WELL_KNOWN_KEYS:-false}" = "true" ]; then
            _warn "Well-known anvil key 사용 중 — DEVNET_ALLOW_WELL_KNOWN_KEYS=true (devnet 전용)"
            _info "  public chain에서는 절대 사용하지 마세요"
        else
            _fail "Well-known key 감지: DEVNET_ALLOW_WELL_KNOWN_KEYS=true 가 설정되지 않음"
            _info "  devnet 전용 사용에 동의하려면 .env에 추가: DEVNET_ALLOW_WELL_KNOWN_KEYS=true"
        fi
    fi
else
    _ok "Well-known key 미사용"
fi

# ---------------------------------------------------------------
# 결과
# ---------------------------------------------------------------
echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "요구사항 확인 완료 — 모든 항목 통과."
else
    echo "ERROR: $ERRORS 개 항목 미충족 — 위 항목을 확인하세요."
    exit 1
fi
