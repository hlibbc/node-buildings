#!/usr/bin/env bash
# check-requirements.sh — Docker 프로젝트 요구사항 확인
set -euo pipefail

ERRORS=0

check_cmd() {
    local cmd="$1" hint="${2:-}"
    if command -v "$cmd" &>/dev/null; then
        echo "  [OK]      $cmd"
    else
        echo "  [MISSING] $cmd${hint:+  ($hint)}"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== check-requirements (ethereum-pos-docker) ==="
echo ""

echo "--- 필수 도구 ---"
check_cmd docker      "https://docs.docker.com/engine/install/"
check_cmd curl
check_cmd jq          "apt install jq"
check_cmd openssl

echo ""
echo "--- Docker 상태 확인 ---"
if docker info &>/dev/null 2>&1; then
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    echo "  [OK]      Docker daemon 실행 중 (${DOCKER_VERSION})"
else
    echo "  [ERROR]   Docker daemon 미실행"
    ERRORS=$((ERRORS + 1))
fi

if docker compose version &>/dev/null 2>&1; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    echo "  [OK]      docker compose v${COMPOSE_VERSION}"
else
    echo "  [ERROR]   docker compose 없음 (Docker Desktop 또는 compose plugin 설치 필요)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "--- .env 파일 확인 ---"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$PROJECT_DIR/.env" ]; then
    echo "  [OK]      .env 존재"
    GETH_VER=$(grep "^GETH_VERSION=" "$PROJECT_DIR/.env" | cut -d= -f2 || echo "")
    PRYSM_VER=$(grep "^PRYSM_VERSION=" "$PROJECT_DIR/.env" | cut -d= -f2 || echo "")
    echo "  GETH_VERSION=${GETH_VER:-<미설정>}"
    echo "  PRYSM_VERSION=${PRYSM_VER:-<미설정>}"
    if [ -z "$GETH_VER" ] || [ -z "$PRYSM_VER" ]; then
        echo "  [ERROR]   GETH_VERSION 또는 PRYSM_VERSION 미설정 — .env 확인"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  [MISSING] .env  →  cp .env.sample .env"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "요구사항 확인 완료 — 모든 항목 통과."
else
    echo "ERROR: $ERRORS 개 항목 미충족."
    exit 1
fi
