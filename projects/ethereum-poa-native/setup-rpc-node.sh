#!/bin/bash

### 커스텀 .env 파일을 받아서 환경 설정에 반영하기 위한 작업
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" ### 현재 실행 중인 스크립트 파일이 위치한 디렉토리의 절대 경로를 구함
ROOT_DIR="$SCRIPT_DIR" # ROOT_DIR을 SCRIPT_DIR과 동일레벨로 설정함
env_file="$SCRIPT_DIR/.env"  # 항상 native/.env 를 사용

for arg in "$@"; do # 스크립트에 전달된 모든 인자($@)를 하나씩 반복하면서 arg 변수에 담음
    case $arg in # 현재 인자(arg)를 패턴 매칭
        --env=* | --e=*) # 인자가 --env=값 또는 --e=값 형태인 경우 (예: --env=.node1.env)
            env_file="${arg#*=}" # '=' 기호 이후의 값만 추출하여 env_file 변수에 저장 (ex. --env=.node1.env → env_file=".node1.env")
            ;; # case $arg in 문 종료
        *)
            ;; # default ('*)') 문 종료
    esac # case 블록 종료
done # for문 종료

if [ -f "$env_file" ]; then
    source "$env_file" # $env_file 파일을 현재 셸에 로드하여 환경 변수들을 설정
else
    echo "Error: $env_file does not exist."
    exit 1
fi

mkdir -p "$CONFIG_DIR" "$BACKUP_DIR" "$EXECUTION_ROOT" # 💡 필요한 디렉토리 자동 생성
echo "== 🛠️ Set ENV $env_file (Direct Geth Execution)\n"

# Geth 바이너리 경로 설정
GETH_BIN="$ROOT_DIR/geth/v1.13.15/geth"

### 도움말 출력함수
func_execution_help()
{
    echo Usage:
    echo "  ./setup-rpc-node.sh [command]"
    echo
    echo Available Commands:
    echo "  init                        Bootstrap and initialize a new genesis block"
    echo "  run                         Run go-ethereum RPC Node (Sync Only) 🚀"
    echo "  attach, a                   Start an interactive JavaScript environment (HTTP RPC)"
    echo "  clean                       Remove blockchain and state databases (PATH:./poa/data)"
    echo "  stop                        Stop the running geth process"
    echo "  status                      Check if geth is running"
    echo "  logs                        Display the live log output from the geth process"
    echo
    echo Global Options:
    echo "  --env=, --e=         Set env Path (DEFAULT .env)"
}

case "$1" in
    "init")
        echo "Run go-ethereum init genesis block -- 🚀"
        # .env의 CHAIN_ID를 genesis config.chainId에 주입하여 초기화
        _GENESIS_TMP="$(mktemp /tmp/genesis.XXXXXX.json)"
        jq --argjson chainId "$CHAIN_ID" '.config.chainId = $chainId' $ROOT_DIR/genesis/genesis.json > "$_GENESIS_TMP"
        $GETH_BIN --datadir $EXECUTION_ROOT/data init "$_GENESIS_TMP"
        rm -f "$_GENESIS_TMP"
        ;;
    "run")
        echo "Run go-ethereum RPC Node (Sync Only) -- 🚀"
        
        # 기존 프로세스가 실행 중인지 확인 (.*rpc 패턴 제거: 실제 cmdline에 "rpc" 문자열 없음)
        if pgrep -f "geth.*--datadir.*$EXECUTION_ROOT/data" > /dev/null; then
            echo "Geth RPC is already running. Stopping first..."
            pkill -2 -f "geth.*--datadir.*$EXECUTION_ROOT/data"
            sleep 2
        fi

        # STATIC_PEER_ENODE가 설정된 경우 static-nodes.json 생성 (--nodiscover 환경에서 peer 연결)
        if [ -n "$STATIC_PEER_ENODE" ]; then
            mkdir -p $EXECUTION_ROOT/data/geth
            jq -n --arg e "$STATIC_PEER_ENODE" '[$e]' > $EXECUTION_ROOT/data/geth/static-nodes.json
        fi
        _NETWORK_ID=${NETWORK_ID:-$CHAIN_ID}

        ### rpc 전용: non-signer, personal/debug/miner/allow-insecure-unlock 제외, authrpc 불필요
        nohup $GETH_BIN \
            --datadir $EXECUTION_ROOT/data \
            --syncmode=full \
            --networkid=$_NETWORK_ID \
            --port=$GETH_PORT \
            --http \
            --http.api=eth,net,txpool \
            --http.addr=0.0.0.0 \
            --http.port=$GETH_HTTP_PORT \
            --http.corsdomain=* \
            --http.vhosts=* \
            --ws \
            --ws.api=eth,net,web3 \
            --ws.addr=0.0.0.0 \
            --ws.port=$GETH_WS_PORT \
            --ws.origins=* \
            --nodiscover \
            > geth-rpc.log 2>&1 &

        echo "Geth RPC Node started in background. Check geth-rpc.log for logs."
        ;;
    "attach"|"a")
        echo "Attaching to geth node via IPC -- 🚀"
        # ipc로 연결
        $GETH_BIN attach $EXECUTION_ROOT/data/geth.ipc
        ;;
    "stop")
        echo "Stopping geth RPC process -- 🛑"
        pkill -2 -f "geth.*--datadir.*$EXECUTION_ROOT/data"
        echo "Geth RPC stopped."
        ;;
    "status")
        if pgrep -f "geth.*--datadir.*$EXECUTION_ROOT/data" > /dev/null; then
            echo "Geth RPC is running."
            ps aux | grep "geth.*--datadir.*$EXECUTION_ROOT/data" | grep -v grep
        else
            echo "Geth RPC is not running."
        fi
        ;;
    "clean")
        echo "Clear go-ethereum RPC DB & Genesis -- 🗑️"
        pkill -f "geth.*--datadir.*$EXECUTION_ROOT/data" 2>/dev/null
        rm -rf $EXECUTION_ROOT/data/geth # Geth 데이터 디렉토리 삭제
        echo "Cleaned RPC blockchain data."
        ;;
    "logs")
        echo "Showing geth RPC logs -- 📋"
        tail -f geth-rpc.log # 실시간 로그 출력
        ;;
    "help" | "-h")
        func_execution_help # 도움말 출력
        ;;
    *)
    func_execution_help
    ;;
esac 