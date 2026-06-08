#!/usr/bin/env bash
# check-requirements.sh — 설치 전 요구사항 확인
# 사용법: ./scripts/common/check-requirements.sh
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=detect-os.sh
source "$SCRIPTS_DIR/detect-os.sh"

OS=$(detect_os)
ARCH=$(detect_arch)

echo "=== check-requirements ==="
echo "OS:   $OS"
echo "Arch: $ARCH"
echo ""

ERRORS=0

check_cmd() {
    local cmd="$1"
    local hint="${2:-}"
    if command -v "$cmd" &>/dev/null; then
        echo "  [OK]      $cmd"
    else
        echo "  [MISSING] $cmd${hint:+ — $hint}"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "--- 필수 도구 ---"
check_cmd curl    "apt install curl"
check_cmd jq      "apt install jq"
check_cmd openssl "apt install openssl"
check_cmd sha256sum "coreutils 패키지"
check_cmd systemctl "systemd 환경 필요"

echo ""
echo "--- 권장 도구 ---"
check_cmd tar
check_cmd envsubst "gettext 패키지: apt install gettext-base"

echo ""
echo "--- OS 확인 ---"
if [ "$OS" = "linux" ]; then
    echo "  [OK]      Linux ($OS/$ARCH)"
else
    echo "  [WARNING] Native 설치는 Linux 전용입니다. 현재 OS: $OS"
    echo "            macOS에서는 스크립트 검토/수정 용도로만 사용 가능합니다."
    ERRORS=$((ERRORS + 1))
fi

if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ]; then
    echo "  [OK]      아키텍처: $ARCH"
else
    echo "  [ERROR]   지원하지 않는 아키텍처: $ARCH (amd64, arm64 지원)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "--- 디스크 공간 (/ 마운트) ---"
if command -v df &>/dev/null; then
    AVAIL_GB=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "?")
    REQUIRED_GB=50
    if [[ "$AVAIL_GB" =~ ^[0-9]+$ ]] && [ "$AVAIL_GB" -ge "$REQUIRED_GB" ]; then
        echo "  [OK]      ${AVAIL_GB}GB 여유 (권장: ${REQUIRED_GB}GB 이상)"
    else
        echo "  [WARNING] ${AVAIL_GB}GB 여유 (권장: ${REQUIRED_GB}GB 이상)"
        echo "            geth 체인 데이터 + beacon 데이터 고려"
    fi
fi

echo ""
echo "--- systemd 실행 환경 ---"
if systemctl is-system-running &>/dev/null || systemctl status &>/dev/null 2>&1; then
    echo "  [OK]      systemd 동작 중"
else
    echo "  [WARNING] systemd 상태 확인 불가 (컨테이너 환경이거나 비-systemd 배포판)"
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "요구사항 확인 완료 — 모든 항목 통과."
else
    echo "ERROR: $ERRORS 개 항목 미충족. 위 항목을 해결 후 재실행하세요."
    exit 1
fi
