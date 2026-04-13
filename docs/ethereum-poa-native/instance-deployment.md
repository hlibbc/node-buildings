# ethereum-poa-native 인스턴스 구축

geth 1.13.15 Clique PoA 테스트망을 두 인스턴스(consensus / rpc)에 구축하는 절차.

---

## 사전 준비

- consensus 인스턴스 1대 + rpc 인스턴스 1대 (각 인스턴스에서 아래 절차 진행)
- 각 인스턴스에 `jq`, `node` 설치
- geth 바이너리는 레포에 포함: `projects/ethereum-poa-native/geth/v1.13.15/geth`
- 이 프로젝트는 **geth 1.13.15 legacy Clique PoA** 기반 — 최신 PoS/Shanghai/Cancun/Prague 미지원
- 컨트랙트 배포 시 `evmVersion: "london"` 전제 (그 이상 미지원)

---

## 1. 레포 클론

```bash
git clone <repo-url>
cd node-buildings/projects/ethereum-poa-native
```

---

## 2. consensus 인스턴스 — env 준비

```bash
cp .env_sample .env
```

최소 설정값 (레포 루트 기준 상대경로, sudo 불필요):

```dotenv
CHAIN_ID=12345
NETWORK_ID=                        # 비워두면 CHAIN_ID 사용

CONFIG_DIR=./var/consensus/config
BACKUP_DIR=./var/consensus/backup
EXECUTION_ROOT=./var/consensus
PASSWORD_ROOT=./var/consensus/config/password.txt

GETH_PORT=30303
GETH_HTTP_PORT=8545
GETH_WS_PORT=8546
GETH_AUTH_RPC_PORT=8551            # geth 1.13.x authrpc 포트 (Clique 미사용, 포트 충돌 방지용)

CONSENSUS_HTTP_ADDR=127.0.0.1      # 외부 공개 금지
MINER_ADDRESS=                     # generate 실행 후 자동 기록됨
```

> `CONFIG_DIR`, `BACKUP_DIR`, `EXECUTION_ROOT` 는 스크립트 시작 시 자동 생성된다.
> `PASSWORD_ROOT` 는 `CONFIG_DIR` 하위 경로로 설정 권장 (`generate` 시 `$CONFIG_DIR/password.txt` 에 저장됨).
> 운영 환경에서는 `/opt/eth/consensus/...` 등 절대경로로 변경.

> **고급:** 같은 머신에서 여러 env 파일을 쓸 경우 `./setup.sh generate --env=<파일>` 형태로 지정 가능 (command 먼저, --env 나중).

---

## 3. consensus — miner 계정 생성

```bash
./setup.sh generate
```

- 무작위 패스워드 생성 → `$CONFIG_DIR/password.txt` 에 저장
- miner 계정 생성 → `MINER_ADDRESS` 가 `.env` 에 자동 기록
- genesis `extradata` 갱신

---

## 4. consensus — genesis 초기화

```bash
./setup.sh init
```

- `.env` 의 `CHAIN_ID` 값으로 초기화됨. 실제 적용 여부는 기동 후 `eth.chainId()` 로 확인 → [verification.md](./verification.md)

---

## 5. consensus — 노드 실행

```bash
./setup.sh run-consensus
```

- 기동 2초 후 프로세스 생존 여부를 자동 확인함. 실패 시 마지막 로그 5줄 출력
- 상태: `./setup.sh status`
- 로그: `tail -f geth.log`

---

## 6. consensus enode 확인

IPC로 접속:

```bash
./setup.sh attach
```

```javascript
admin.nodeInfo.enode
// "enode://<pubkey>@<consensus-ip>:30303"
```

> 출력된 enode의 IP가 `127.0.0.1` 이면 consensus 인스턴스의 실제 IP로 교체한다. 이 값을 그대로 `STATIC_PEER_ENODE` 에 입력.

---

## 7. rpc 인스턴스 — env 준비

rpc 인스턴스에서:

```bash
cp .env_sample .env
```

최소 설정값 (레포 루트 기준 상대경로, sudo 불필요):

```dotenv
CHAIN_ID=12345                     # consensus 와 동일
NETWORK_ID=                        # 비워두면 CHAIN_ID 사용

CONFIG_DIR=./var/rpc/config
BACKUP_DIR=./var/rpc/backup
EXECUTION_ROOT=./var/rpc

GETH_PORT=30303
GETH_HTTP_PORT=8545
GETH_WS_PORT=8546
GETH_AUTH_RPC_PORT=8551            # geth 1.13.x authrpc 포트 (Clique 미사용, 포트 충돌 방지용)

# 6단계에서 얻은 enode URL. IP가 127.0.0.1 이면 consensus 인스턴스 실제 IP 로 교체 후 입력
STATIC_PEER_ENODE=enode://<pubkey>@<consensus-ip>:30303
```

> `PASSWORD_ROOT` 는 rpc 노드에서 사용하지 않으므로 생략.
> `CONFIG_DIR`, `BACKUP_DIR`, `EXECUTION_ROOT` 는 스크립트 시작 시 자동 생성된다.

---

## 8. rpc — genesis 초기화

```bash
./setup-rpc-node.sh init
```

---

## 9. rpc — 노드 실행

```bash
./setup-rpc-node.sh run
```

- 기동 2초 후 프로세스 생존 여부를 자동 확인함. 실패 시 마지막 로그 5줄 출력
- 상태: `./setup-rpc-node.sh status`
- 로그: `tail -f geth-rpc.log`

---

## 10. 검증

→ [verification.md](./verification.md)
