#!/usr/bin/env bash
# load-env.sh — .env 파일 로드 유틸리티
# 직접 실행하지 말고 source로 사용하세요.
#
# 사용법 (각 스크립트 상단):
#   SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
#   PROJECT_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"
#   source "$SCRIPTS_DIR/../common/load-env.sh"
#   load_env "$@"

load_env() {
    local env_file
    local _project_dir="${PROJECT_DIR:-}"

    # --env= 인수 파싱
    env_file="${_project_dir}/.env"
    for _arg in "$@"; do
        case "$_arg" in
            --env=*) env_file="${_arg#*=}"; break ;;
        esac
    done

    # 절대경로 변환
    if [[ "$env_file" != /* ]]; then
        env_file="$(cd "$(dirname "$env_file")" 2>/dev/null && pwd)/$(basename "$env_file")"
    fi

    if [ ! -f "$env_file" ]; then
        echo "ERROR: env 파일을 찾을 수 없습니다: $env_file" >&2
        echo "       .env.node0.sample 또는 .env.node1.sample에서 복사하세요:" >&2
        echo "         cp .env.node0.sample .env" >&2
        echo "       또는 --env= 옵션으로 파일을 지정하세요." >&2
        return 1
    fi

    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a

    echo "ENV 로드: $env_file  (NODE_NAME=${NODE_NAME:-<미설정>})"
}
