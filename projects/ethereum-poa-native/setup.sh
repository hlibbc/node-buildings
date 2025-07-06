#!/bin/bash

### 커스텀 .env 파일을 받아서 환경 설정에 반영하기 위한 작업
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" ### 현재 실행 중인 스크립트 파일이 위치한 디렉토리의 절대 경로를 구함
ROOT_DIR="$SCRIPT_DIR" # ROOT_DIR을 SCRIPT_DIR과 동일레벨로 설정함
env_file="$SCRIPT_DIR/.env"  # 항상 $SCRIPT_DIR/.env 를 사용

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
    echo "  ./setup-concensus-node.sh [command]"
    echo
    echo Available Commands:
    echo "  new-account, new            Create a new account (PATH:./poa/data/keystore)"
    echo "  list-account, list          Print summary of existing accounts"
    echo "  generate                    Set POA Miner"
    echo "  init                        Bootstrap and initialize a new genesis block"
    echo "  run-consensus               Run go-ethereum Execution Layer Node (consensus) 🚀"
    echo "  run-rpc                     Run go-ethereum RPC Node (Sync Only) 🚀"
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
    "new-account"|"new")
        # 새로운 계정을 생성 (생성된 keystore는 $EXECUTION_ROOT/data/keystore 밑에 저장)
        # $PASSWORD_ROOT의 내용을 읽어 계정 암호로 설정
        echo "Run go-ethereum account new -- 🚀"
        $GETH_BIN account new --datadir $EXECUTION_ROOT/data --password $PASSWORD_ROOT
        ;;
    "list-account"|"list")
        # 생성된 계정 목록을 출력
        echo "Run go-ethereum account list -- 🚀"
        $GETH_BIN account list --datadir $EXECUTION_ROOT/data 
        ;;
    "generate")
        echo "generate Miner Address -- 🚀"
        # 무작위 비밀번호를 생성해 password.txt에 저장
        < /dev/urandom LC_CTYPE=C tr -dc 'A-Za-z0-9' | head -c 16 > $CONFIG_DIR/password.txt
        # 해당 비밀번호로 계정을 생성하고, 생성된 주소를 파싱하여 변수에 저장
        _MINER_ADDRESS=`$GETH_BIN account new --datadir $EXECUTION_ROOT/data --password $PASSWORD_ROOT  | grep "Public address of the key:" | awk '{print $6}' | tr -d '{}'`
        # .env 파일에서 기존 MINER_ADDRESS 값을 새로 생성한 값으로 치환
        sed "s|^MINER_ADDRESS=.*|MINER_ADDRESS=$_MINER_ADDRESS|" .env > .env.tmp && mv .env.tmp .env
        # extradata 생성: 마이너 주소를 기반으로 node generate-extradata.js 실행
        EXTRA_DATA=`export MINER_ADDRESS=$_MINER_ADDRESS; node generate-extradata.js`
        # genesis.json 파일의 extradata 필드 업데이트
        jq --arg extraData "$EXTRA_DATA" '.extradata = $extraData' $ROOT_DIR/genesis/genesis.json > temp.json && mv temp.json $ROOT_DIR/genesis/genesis.json
        ;;
    "init")
        echo "Run go-ethereum init genesis block -- 🚀"
        # 지정된 genesis.json을 사용하여 블록체인 초기화
        $GETH_BIN --datadir $EXECUTION_ROOT/data init $ROOT_DIR/genesis/genesis.json
        ;;
    "run-consensus")
        echo "Run Execution Layer go-ethereum Node -- 🚀"
        
        # 기존 프로세스가 실행 중인지 확인
        if pgrep -f "geth.*--datadir.*$EXECUTION_ROOT/data" > /dev/null; then
            echo "Geth is already running. Stopping first..."
            pkill -2 -f "geth.*--datadir.*$EXECUTION_ROOT/data" # 실행 중이면 먼저 프로세스 kill (SIGINT) 
            sleep 2
        fi
        
        ### 백그라운드에서 geth 실행 (--authrpc.jwtsecret에 의해 jwtsecret 파일은 geth가 처음 실행될 때 자동으로 생성)
        nohup $GETH_BIN \
            --datadir $EXECUTION_ROOT/data \
            --syncmode=full \
            --networkid=$CHAIN_ID \
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
            --authrpc.vhosts=* \
            --authrpc.addr=0.0.0.0 \
            --authrpc.port=$GETH_AUTH_RPC_PORT \
            --authrpc.jwtsecret=$CONFIG_DIR/jwtsecret \
            --mine \
            --miner.etherbase=$MINER_ADDRESS \
            --unlock=$MINER_ADDRESS \
            --allow-insecure-unlock \
            --password=$PASSWORD_ROOT \
            --nodiscover \
            > geth.log 2>&1 &
        
        echo "Geth started in background (consensus). Check geth.log for logs."
        ;;
    "run-rpc")
        echo "Run go-ethereum RPC Node (Sync Only) -- 🚀"
        
        # 기존 프로세스가 실행 중인지 확인
        if pgrep -f "geth.*--datadir.*$EXECUTION_ROOT/data.*rpc" > /dev/null; then
            echo "Geth RPC is already running. Stopping first..."
            pkill -2 -f "geth.*--datadir.*$EXECUTION_ROOT/data.*rpc" # 실행 중이면 먼저 프로세스 kill (SIGINT) 
            sleep 2
        fi
        
        ### 백그라운드에서 geth 실행 (RPC 노드 - 블록 생성 없이 동기화만)
        nohup $GETH_BIN \
            --datadir $EXECUTION_ROOT/data \
            --syncmode=full \
            --networkid=$CHAIN_ID \
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
            --authrpc.vhosts=* \
            --authrpc.addr=0.0.0.0 \
            --authrpc.port=$GETH_AUTH_RPC_PORT \
            --authrpc.jwtsecret=$CONFIG_DIR/jwtsecret \
            --nodiscover \
            > geth-rpc.log 2>&1 &
        
        echo "Geth RPC Node started in background (rpc only). Check geth-rpc.log for logs."
        ;;
    "attach"|"a")
        echo "Attaching to geth node via IPC -- 🚀"
        # ipc로 연결
        $GETH_BIN attach $EXECUTION_ROOT/data/geth.ipc
        ;;
    "stop")
        echo "Stopping geth process -- 🛑"
        # geth 프로세스 kill (SIGINT) -> 중지
        pkill -2 -f "geth.*--datadir.*$EXECUTION_ROOT/data"
        echo "Geth stopped."
        ;;
    "status")
        if pgrep -f "geth.*--datadir.*$EXECUTION_ROOT/data" > /dev/null; then
            echo "Geth is running."
            ps aux | grep "geth.*--datadir.*$EXECUTION_ROOT/data" | grep -v grep # 실행 중인 Geth 프로세스 상세 출력
        else
            echo "Geth is not running."
        fi
        ;;
    "clean")
        echo "Clear go-ethereum DB & Genesis -- 🗑️"
        pkill -f "geth.*--datadir.*$EXECUTION_ROOT/data" 2>/dev/null
        rm -rf $EXECUTION_ROOT/data/geth # Geth 데이터 디렉토리 삭제
        echo "Cleaned blockchain data."
        ;;
    "logs")
        echo "Showing geth logs -- 📋"
        tail -f geth.log # 실시간 로그 출력
        ;;
    "help" | "-h")
        func_execution_help # 도움말 출력
        ;;
    *)
    func_execution_help
    ;;
esac 