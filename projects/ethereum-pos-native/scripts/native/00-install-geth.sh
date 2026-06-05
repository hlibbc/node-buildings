#!/usr/bin/env bash
# 00-install-geth.sh — Geth 공식 apt repository를 통한 설치
#
# 설치 방식: Ethereum Foundation 공식 PPA (ppa:ethereum/ethereum)
# 검증 방식: apt 패키지 서명 검증 (GPG key 8A16544F)
#            비공식 바이너리 / 임의 mirror / 무검증 설치 금지
#
# 지원 OS:
#   Ubuntu 22.04+  — add-apt-repository 방식 (software-properties-common 필요)
#   Debian 12+     — 수동 PPA 설정 방식
#
# 설치 위치:
#   /usr/bin/geth           (apt 관리)
#   /usr/local/bin/geth     (symlink — TASK.md 경로 준수)
#
# 기록:  versions.lock (GETH_VERSION, GETH_APT_PACKAGE, GETH_APT_SOURCE)
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"
VERSIONS_LOCK="$PROJECT_DIR/versions.lock"

# shellcheck source=../common/detect-os.sh
source "$SCRIPTS_DIR/../common/detect-os.sh"

OS=$(detect_os)
if [ "$OS" != "linux" ]; then
    echo "ERROR: Geth apt 설치는 Linux 전용입니다. 현재 OS: $OS"
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: root 또는 sudo로 실행해야 합니다."
    exit 1
fi

echo "=== Geth 설치 (공식 apt repository: ppa:ethereum/ethereum) ==="

# --- 배포판 감지 ---
DISTRO=""
CODENAME=""
if [ -f /etc/os-release ]; then
    DISTRO=$(. /etc/os-release && echo "${ID:-}")
    # Ubuntu는 UBUNTU_CODENAME, Debian은 VERSION_CODENAME
    CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
fi
echo "배포판: ${DISTRO:-unknown}  코드명: ${CODENAME:-unknown}"

PPA_KEY_FINGERPRINT="8A16544F"
PPA_LAUNCHPAD_URL="https://ppa.launchpadcontent.net/ethereum/ethereum/ubuntu"
PPA_KEYSERVER="https://keyserver.ubuntu.com"
# Debian에서 Ubuntu PPA를 사용할 때의 Ubuntu codename
# Debian 자체 VERSION_CODENAME(bookworm 등)은 PPA에서 인식 안 됨
GETH_PPA_UBUNTU_CODENAME="${GETH_PPA_UBUNTU_CODENAME:-jammy}"

# --- Ubuntu: add-apt-repository 방식 ---
if [ "$DISTRO" = "ubuntu" ]; then
    echo ""
    echo "Ubuntu 감지: add-apt-repository 방식 사용..."
    apt-get install -y --no-install-recommends software-properties-common
    add-apt-repository -y ppa:ethereum/ethereum
    apt-get update -qq

# --- Debian: 수동 PPA 설정 방식 ---
elif [ "$DISTRO" = "debian" ]; then
    echo ""
    echo "Debian 감지: 수동 PPA 설정 방식 사용..."
    apt-get install -y --no-install-recommends curl gnupg

    # GPG 키 가져오기 (keyserver 우선, 실패 시 HTTPS fallback)
    echo "  GPG 키 가져오는 중 (${PPA_KEY_FINGERPRINT})..."
    if gpg --keyserver "${PPA_KEYSERVER}" --recv-keys "$PPA_KEY_FINGERPRINT" 2>/dev/null; then
        gpg --export "$PPA_KEY_FINGERPRINT" | tee /etc/apt/trusted.gpg.d/ethereum.gpg > /dev/null
    else
        curl -fsSL "${PPA_KEYSERVER}/pks/lookup?op=get&search=0x${PPA_KEY_FINGERPRINT}" \
            | gpg --dearmor -o /etc/apt/trusted.gpg.d/ethereum.gpg
    fi
    echo "  GPG 키 설치: /etc/apt/trusted.gpg.d/ethereum.gpg"

    # Debian에서 Ubuntu PPA 사용 시 반드시 Ubuntu codename 지정
    # Debian 자체 codename(bookworm 등)은 PPA에서 인식 안 됨
    echo "  Ubuntu PPA codename: ${GETH_PPA_UBUNTU_CODENAME}"
    echo "  (변경 방법: GETH_PPA_UBUNTU_CODENAME=noble npm run install:geth)"
    echo "deb ${PPA_LAUNCHPAD_URL} ${GETH_PPA_UBUNTU_CODENAME} main" | \
        tee /etc/apt/sources.list.d/ethereum.list > /dev/null
    echo "  apt source: /etc/apt/sources.list.d/ethereum.list"
    apt-get update -qq

else
    echo "ERROR: 지원하지 않는 배포판: '${DISTRO}'"
    echo "       Ubuntu 22.04+ 또는 Debian 12+ 이 필요합니다."
    echo "       /etc/os-release 파일 확인: $(cat /etc/os-release 2>/dev/null || echo '없음')"
    exit 1
fi

# --- 설치 ---
echo ""
echo "Geth 설치 중..."
apt-get install -y geth

# 버전 고정 (accidental upgrade 방지)
apt-mark hold geth
echo "  apt-mark hold geth 적용 (업그레이드 차단)"
echo "  해제 방법: sudo apt-mark unhold geth"

# --- symlink (TASK.md /usr/local/bin/geth 경로 준수) ---
ln -sf /usr/bin/geth /usr/local/bin/geth
echo "  symlink: /usr/local/bin/geth → /usr/bin/geth"

# --- 버전 및 apt 정보 수집 ---
echo ""
GETH_VERSION=$(geth version 2>/dev/null | grep "^Version:" | awk '{print $2}' | head -1)
GETH_APT_PACKAGE=$(apt-cache policy geth 2>/dev/null | grep "Installed:" | awk '{print $2}')
GETH_APT_SOURCE=$(apt-cache policy geth 2>/dev/null \
    | grep -E "(ppa\.launchpad|launchpadcontent|ethereum)" | head -1 \
    | awk '{print $2}' || echo "ppa:ethereum/ethereum")

echo "=== 설치 확인 ==="
geth version 2>/dev/null | head -5
echo ""
echo "apt-cache policy geth:"
apt-cache policy geth 2>/dev/null | head -8
echo ""
echo "apt source:"
cat /etc/apt/sources.list.d/ethereum.list 2>/dev/null || \
    apt-cache policy geth 2>/dev/null | grep "ppa\|launchpad" | head -3 | sed 's/^/  /'

# --- versions.lock 갱신 ---
_update_lock() {
    local key="$1"
    local val="$2"
    if grep -q "^${key}=" "$VERSIONS_LOCK" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$VERSIONS_LOCK"
    else
        echo "${key}=${val}" >> "$VERSIONS_LOCK"
    fi
}

# apt 기반 Geth: GETH_DOWNLOAD_URL/SHA256 대신 apt 관련 항목 기록
_update_lock "GETH_VERSION"             "$GETH_VERSION"
_update_lock "GETH_APT_PACKAGE"         "$GETH_APT_PACKAGE"
_update_lock "GETH_APT_SOURCE"          "ppa:ethereum/ethereum"
_update_lock "GETH_APT_KEY_FINGERPRINT" "$PPA_KEY_FINGERPRINT"

echo ""
echo "versions.lock 갱신:"
echo "  GETH_VERSION=$GETH_VERSION"
echo "  GETH_APT_PACKAGE=$GETH_APT_PACKAGE"
echo ""
echo "다음 단계: npm run install:prysm"
