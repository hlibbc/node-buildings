#!/usr/bin/env bash
# 01-install-prysm.sh — Prysm 최신 stable 버전 다운로드 및 설치
#
# 릴리즈 소스: OffchainLabs/prysm (Arbitrum 호환 Prysm fork, 기본값)
#   변경 방법: PRYSM_GITHUB_ORG=prysmaticlabs sudo npm run install:prysm
#
# checksum 방식:
#   1순위: checksums.txt (prysmaticlabs 형식)
#   2순위: 개별 asset .sha256 파일 (OffchainLabs 형식 대응 fallback)
#   어느 방식으로도 검증 불가 시 설치 중단 (무검증 설치 금지)
#
# 대상: Linux amd64 / arm64
# 출력: /usr/local/bin/{beacon-chain,validator,prysmctl}
# 기록: versions.lock
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"
VERSIONS_LOCK="$PROJECT_DIR/versions.lock"
INSTALL_DIR="/usr/local/bin"

# shellcheck source=../common/detect-os.sh
source "$SCRIPTS_DIR/../common/detect-os.sh"

OS=$(detect_os)
ARCH=$(detect_arch)

if [ "$OS" != "linux" ]; then
    echo "ERROR: Prysm native 설치는 Linux 전용입니다. 현재 OS: $OS"
    exit 1
fi
if [ "$ARCH" = "unsupported" ]; then
    echo "ERROR: 지원하지 않는 아키텍처: $(uname -m)"
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: /usr/local/bin 에 설치하려면 root 또는 sudo로 실행해야 합니다."
    exit 1
fi

echo "=== Prysm 설치 ==="
echo "OS: $OS / Arch: $ARCH"

# GitHub org — 기본값 OffchainLabs (Arbitrum 호환 fork)
# upstream 사용: PRYSM_GITHUB_ORG=prysmaticlabs sudo npm run install:prysm
PRYSM_GITHUB_ORG="${PRYSM_GITHUB_ORG:-OffchainLabs}"
echo "Prysm 릴리즈 소스: github.com/${PRYSM_GITHUB_ORG}/prysm"

# GitHub Releases API에서 최신 stable 버전 조회
GITHUB_API="https://api.github.com/repos/${PRYSM_GITHUB_ORG}/prysm/releases/latest"
echo "최신 Prysm 버전 조회 중..."
RELEASE_JSON=$(curl -fsSL \
    -H "Accept: application/vnd.github.v3+json" \
    "$GITHUB_API")

PRYSM_VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
if [ -z "$PRYSM_VERSION" ]; then
    echo "ERROR: Prysm 버전 정보를 가져오지 못했습니다."
    echo "       org: $PRYSM_GITHUB_ORG — 릴리즈가 없을 경우 prysmaticlabs로 전환:"
    echo "       PRYSM_GITHUB_ORG=prysmaticlabs sudo npm run install:prysm"
    exit 1
fi
echo "최신 Prysm: v${PRYSM_VERSION}  (${PRYSM_GITHUB_ORG}/prysm)"

BASE_URL="https://github.com/${PRYSM_GITHUB_ORG}/prysm/releases/download/v${PRYSM_VERSION}"
BEACON_URL="${BASE_URL}/beacon-chain-v${PRYSM_VERSION}-linux-${ARCH}"
VALIDATOR_URL="${BASE_URL}/validator-v${PRYSM_VERSION}-linux-${ARCH}"
PRYSMCTL_URL="${BASE_URL}/prysmctl-v${PRYSM_VERSION}-linux-${ARCH}"
CHECKSUMS_URL="${BASE_URL}/checksums.txt"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# checksum 파일 다운로드 (checksums.txt — prysmaticlabs 형식)
# OffchainLabs 릴리즈가 checksums.txt를 제공하지 않는 경우 fallback으로 .sha256 파일 사용
HAVE_CHECKSUMS_TXT=false
echo "checksum 파일 다운로드 시도: $CHECKSUMS_URL"
if curl -fsSL "$CHECKSUMS_URL" -o "$TMP_DIR/checksums.txt" 2>/dev/null; then
    HAVE_CHECKSUMS_TXT=true
    echo "  checksums.txt 다운로드 완료."
else
    echo "  checksums.txt 없음 — asset별 .sha256 파일 방식으로 전환합니다."
    echo "  (${PRYSM_GITHUB_ORG}/prysm 릴리즈가 checksums.txt를 제공하지 않는 경우 정상)"
fi

_download_and_verify() {
    local dest_name="$1"  # 최종 설치 파일명 (예: beacon-chain)
    local url="$2"        # 다운로드 URL
    local dest="$3"       # 설치 경로
    # asset_name: URL의 basename (예: beacon-chain-v5.3.2-linux-amd64)
    local asset_name
    asset_name=$(basename "$url")

    echo ""
    echo "--- $dest_name (asset: $asset_name) ---"
    echo "  URL: $url"
    curl -fL --progress-bar "$url" -o "$TMP_DIR/$asset_name"

    local sha256=""

    # 1순위: checksums.txt에서 asset_name 조회 (sha256: prefix 처리 포함)
    if [ "$HAVE_CHECKSUMS_TXT" = "true" ]; then
        sha256=$(grep -F "$asset_name" "$TMP_DIR/checksums.txt" 2>/dev/null \
            | awk '{print $1}' | sed 's/^sha256://' | head -1)
        if [ -n "$sha256" ]; then
            echo "  checksum 소스: checksums.txt"
        else
            echo "  checksums.txt에 '$asset_name' 항목 없음 — .sha256 파일 fallback 시도..."
        fi
    fi

    # 2순위: 개별 asset .sha256 파일
    if [ -z "$sha256" ]; then
        local sha256_url="${url}.sha256"
        echo "  .sha256 URL: ${sha256_url}"
        if curl -fsSL "$sha256_url" -o "$TMP_DIR/${asset_name}.sha256" 2>/dev/null; then
            sha256=$(awk '{print $1}' "$TMP_DIR/${asset_name}.sha256" | sed 's/^sha256://' | head -1)
            if [ -n "$sha256" ]; then
                echo "  checksum 소스: ${asset_name}.sha256"
            fi
        fi
    fi

    # 어느 방식으로도 sha256을 얻지 못하면 설치 중단
    if [ -z "$sha256" ]; then
        echo "  ERROR: checksum을 얻지 못했습니다."
        echo "         checksums.txt: ${HAVE_CHECKSUMS_TXT}"
        echo "         .sha256 URL: ${url}.sha256"
        echo "         무검증 바이너리 설치는 허용하지 않습니다."
        if [ "$HAVE_CHECKSUMS_TXT" = "true" ]; then
            echo "  checksums.txt 내용 (앞 15줄):"
            head -15 "$TMP_DIR/checksums.txt" | sed 's/^/    /'
        fi
        exit 1
    fi

    local actual
    actual=$(sha256sum "$TMP_DIR/$asset_name" | awk '{print $1}')

    if [ "$sha256" != "$actual" ]; then
        echo "  ERROR: SHA256 불일치!"
        echo "    예상: $sha256"
        echo "    실제: $actual"
        exit 1
    fi
    echo "  SHA256 검증 완료: $actual"

    install -m 755 "$TMP_DIR/$asset_name" "$dest"
    echo "  설치: $dest"
    echo "    $("$dest" --version 2>/dev/null || echo '(버전 확인 실패 — 첫 실행 시 약관 동의 필요)')"
}

_download_and_verify "beacon-chain" "$BEACON_URL"  "$INSTALL_DIR/beacon-chain"
_download_and_verify "validator"    "$VALIDATOR_URL" "$INSTALL_DIR/validator"
_download_and_verify "prysmctl"     "$PRYSMCTL_URL"  "$INSTALL_DIR/prysmctl"

# SHA256 값 수집 (versions.lock용)
# 다운로드 파일은 asset_name(버전 포함) 기준으로 저장되어 있음
BEACON_ASSET_NAME=$(basename "$BEACON_URL")
VALIDATOR_ASSET_NAME=$(basename "$VALIDATOR_URL")
PRYSMCTL_ASSET_NAME=$(basename "$PRYSMCTL_URL")
BEACON_SHA256=$(sha256sum "$TMP_DIR/$BEACON_ASSET_NAME"    | awk '{print $1}')
VALIDATOR_SHA256=$(sha256sum "$TMP_DIR/$VALIDATOR_ASSET_NAME" | awk '{print $1}')
PRYSMCTL_SHA256=$(sha256sum "$TMP_DIR/$PRYSMCTL_ASSET_NAME"  | awk '{print $1}')

# versions.lock 갱신
_update_lock() {
    local key="$1"
    local val="$2"
    if grep -q "^${key}=" "$VERSIONS_LOCK" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$VERSIONS_LOCK"
    else
        echo "${key}=${val}" >> "$VERSIONS_LOCK"
    fi
}

_update_lock "PRYSM_VERSION"            "$PRYSM_VERSION"
_update_lock "BEACON_CHAIN_DOWNLOAD_URL" "$BEACON_URL"
_update_lock "VALIDATOR_DOWNLOAD_URL"   "$VALIDATOR_URL"
_update_lock "PRYSMCTL_DOWNLOAD_URL"    "$PRYSMCTL_URL"
_update_lock "BEACON_CHAIN_SHA256"      "$BEACON_SHA256"
_update_lock "VALIDATOR_SHA256"         "$VALIDATOR_SHA256"
_update_lock "PRYSMCTL_SHA256"          "$PRYSMCTL_SHA256"

echo ""
echo "=== Prysm 설치 완료 ==="
echo "versions.lock 갱신:"
echo "  PRYSM_VERSION=$PRYSM_VERSION"
echo ""
echo "다음 단계 (node0에서만): npm run generate"
