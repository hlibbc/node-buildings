#!/usr/bin/env bash
# 04-install-systemd-services.sh — systemd service 파일 설치
# 처리 순서:
#   1. ethereum 시스템 사용자 생성 (없는 경우)
#   2. 데이터/로그 디렉토리 생성 및 권한 설정
#   3. env 파일을 /etc/ethereum-pos-native/<NODE_NAME>.env 에 복사
#   4. wrapper 스크립트를 /usr/local/bin/ 에 설치
#   5. service template에서 NODE_NAME 치환 후 /etc/systemd/system/ 에 설치
#   6. systemctl daemon-reload
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"
SYSTEMD_TEMPLATE_DIR="$PROJECT_DIR/systemd"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"

# --- env 로드 ---
ENV_FILE="$PROJECT_DIR/.env"
for _arg in "$@"; do
    case "$_arg" in --env=*) ENV_FILE="${_arg#*=}"; break ;; esac
done
[ -f "$ENV_FILE" ] || { echo "ERROR: env 파일 없음: $ENV_FILE"; exit 1; }
set -a; source "$ENV_FILE"; set +a
echo "ENV: $ENV_FILE  (NODE_NAME=${NODE_NAME})"

# --- 변수 기본값 ---
CONFIG_ROOT="${CONFIG_ROOT:-/etc/ethereum-pos-native}"
EXECUTION_ROOT="${EXECUTION_ROOT:-/var/lib/ethereum-pos-native/geth}"
BEACON_ROOT="${BEACON_ROOT:-/var/lib/ethereum-pos-native/prysm-beacon}"
VALIDATOR_ROOT="${VALIDATOR_ROOT:-/var/lib/ethereum-pos-native/prysm-validator}"
LOG_ROOT="${LOG_ROOT:-/var/log/ethereum-pos-native}"
NODE_NAME="${NODE_NAME:?'ERROR: NODE_NAME이 설정되지 않았습니다.'}"

echo ""
echo "=== systemd 서비스 설치: $NODE_NAME ==="

# --- 1. ethereum 사용자 생성 ---
if ! id ethereum &>/dev/null 2>&1; then
    echo "시스템 사용자 'ethereum' 생성 중..."
    useradd --system --no-create-home --shell /usr/sbin/nologin ethereum
    echo "  생성 완료: ethereum"
else
    echo "  사용자 'ethereum' 이미 존재"
fi

# --- 2. 디렉토리 생성 및 권한 설정 ---
# chown -R 사용 이유:
#   geth init (03-init-geth.sh)이 root로 실행되면 chaindata가 root 소유로 생성됨.
#   재귀 chown으로 이미 생성된 하위 디렉토리(chaindata, beaconchaindata 등)까지 일괄 수정.
echo ""
echo "디렉토리 생성 및 권한 설정 (chown -R)..."
for _dir in "$CONFIG_ROOT" "$EXECUTION_ROOT" "$BEACON_ROOT" "$VALIDATOR_ROOT" "$LOG_ROOT"; do
    mkdir -p "$_dir"
    chown -R ethereum:ethereum "$_dir"
    echo "  $_dir"
done
chmod 750 "$CONFIG_ROOT"

# jwtsecret: ethereum 그룹만 읽기 가능
if [ -f "$CONFIG_ROOT/jwtsecret" ]; then
    chown ethereum:ethereum "$CONFIG_ROOT/jwtsecret"
    chmod 640 "$CONFIG_ROOT/jwtsecret"
fi

# --- 3. env 파일 복사 ---
DEST_ENV="$CONFIG_ROOT/${NODE_NAME}.env"
echo ""
echo "env 파일 복사: $ENV_FILE → $DEST_ENV"
cp "$ENV_FILE" "$DEST_ENV"
chown root:ethereum "$DEST_ENV"
chmod 640 "$DEST_ENV"

# --- 4. wrapper 스크립트 설치 ---
# geth-pos-wrapper / beacon-pos-wrapper: STATIC_BOOTNODES / STATIC_ENRS 조건부 처리
echo ""
echo "wrapper 스크립트 설치..."
install -m 755 "$SCRIPTS_DIR/geth-wrapper.sh"   "/usr/local/bin/geth-pos-wrapper"
install -m 755 "$SCRIPTS_DIR/beacon-wrapper.sh" "/usr/local/bin/beacon-pos-wrapper"
echo "  /usr/local/bin/geth-pos-wrapper"
echo "  /usr/local/bin/beacon-pos-wrapper"

# --- 5. service 파일 설치 ---
echo ""
echo "service 파일 설치..."

_install_service() {
    local template="$1"
    local service_name="$2"
    local dest="$SYSTEMD_SYSTEM_DIR/${service_name}.service"

    if [ ! -f "$template" ]; then
        echo "ERROR: template 없음: $template"
        exit 1
    fi

    # %NODE_NAME% 치환 (install-time 값)
    sed "s|%NODE_NAME%|${NODE_NAME}|g" "$template" > "$dest"
    echo "  $dest"
}

_install_service "$SYSTEMD_TEMPLATE_DIR/geth.service.template"           "eth-pos-geth-${NODE_NAME}"
_install_service "$SYSTEMD_TEMPLATE_DIR/prysm-beacon.service.template"   "eth-pos-beacon-${NODE_NAME}"
_install_service "$SYSTEMD_TEMPLATE_DIR/prysm-validator.service.template" "eth-pos-validator-${NODE_NAME}"

# --- 6. daemon-reload ---
echo ""
echo "systemctl daemon-reload..."
systemctl daemon-reload

echo ""
echo "=== 설치 완료 ==="
echo "서비스 이름:"
echo "  eth-pos-geth-${NODE_NAME}"
echo "  eth-pos-beacon-${NODE_NAME}"
echo "  eth-pos-validator-${NODE_NAME}"
echo ""
echo "다음 단계: npm run start"
echo ""
echo "TIP: 서비스 상태 확인:"
echo "  systemctl status eth-pos-geth-${NODE_NAME}"
echo "  journalctl -u eth-pos-geth-${NODE_NAME} -f"
