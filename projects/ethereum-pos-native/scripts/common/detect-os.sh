#!/usr/bin/env bash
# detect-os.sh — OS/아키텍처 감지 함수 모음
# 사용법: source scripts/common/detect-os.sh

detect_os() {
    local os
    os="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    case "$os" in
        linux*)  echo "linux" ;;
        darwin*) echo "darwin" ;;
        *)       echo "unsupported" ;;
    esac
}

detect_arch() {
    local arch
    arch="$(uname -m 2>/dev/null)"
    case "$arch" in
        x86_64)          echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *)               echo "unsupported" ;;
    esac
}
