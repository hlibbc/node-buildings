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

> 출력된 enode의 IP가 `127.0.0.1` 이면 consensus 인스턴스의 실제 IP로 교체한다. 이 enode URL 을 메모해 둔다 — Step 10 수동 peer 연결에서 사용한다.

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

# STATIC_PEER_ENODE: 현재 구현이 생성하는 static-nodes.json 은 geth 1.13.15 에서 ignored 됨
# 자동 peer 연결 실효 없음 → peer 연결은 Step 10 수동 addPeer 로 처리
# STATIC_PEER_ENODE=
```

> `PASSWORD_ROOT` 는 rpc 노드에서 사용하지 않으므로 생략.
> `CONFIG_DIR`, `BACKUP_DIR`, `EXECUTION_ROOT` 는 스크립트 시작 시 자동 생성된다.
> `STATIC_PEER_ENODE` 는 현재 운영 절차에서 필수가 아니다. peer 연결은 Step 10에서 수동으로 처리한다.

---

## 8. rpc — genesis 배포 및 초기화

`genesis/genesis.json` 은 체인 전체의 단일 원본 파일이다. rpc node 는 consensus node 에서 확정된 동일한 파일을 그대로 사용해야 한다.

**Clique PoA 에서 `extraData` 에는 signer 목록이 인코딩된다. `extraData` 가 다르면 같은 `CHAIN_ID` 라도 다른 체인으로 분기된다.**

### 8-1. genesis.json 복사

consensus 인스턴스에서 rpc 인스턴스로 파일을 전달한다:

```bash
# consensus 인스턴스에서 실행
scp ./genesis/genesis.json <rpc-user>@<rpc-ip>:<repo-path>/genesis/genesis.json
```

### 8-2. rpc datadir 초기화

기존 datadir 가 있으면 반드시 삭제 후 재초기화한다. `genesis.json` 파일만 교체해서는 안 된다.

```bash
# rpc 인스턴스에서 실행
./setup-rpc-node.sh clean
./setup-rpc-node.sh init
```

> genesis 동일성 확인 방법 → [verification.md](./verification.md)

---

## 9. rpc — 노드 실행

```bash
./setup-rpc-node.sh run
```

- 기동 2초 후 프로세스 생존 여부를 자동 확인함. 실패 시 마지막 로그 5줄 출력
- 상태: `./setup-rpc-node.sh status`
- 로그: `tail -f geth-rpc.log`

---

## 10. rpc — peer 연결 (수동)

현재 구현은 `STATIC_PEER_ENODE` 값을 `static-nodes.json` 으로 생성하지만, geth 1.13.15 에서 이 방식은 deprecated 되어 ignored 된다. 이로 인해 **peer 연결이 자동으로 성립하지 않는다.** 현행 임시 운영 절차는 수동 `admin.addPeer()` 다.

rpc 인스턴스에서:

```bash
./setup-rpc-node.sh attach
```

콘솔에서:

```javascript
// Step 6에서 메모한 enode (IP 가 127.0.0.1 이면 consensus 실제 IP 로 교체)
admin.addPeer("enode://<pubkey>@<consensus-real-ip>:<GETH_PORT>")
// true

net.peerCount    // 기대값: 1 이상
admin.peers      // 기대값: consensus 노드 정보 포함
eth.blockNumber  // 기대값: consensus 블록 번호를 따라 증가
```

> **주의:** `admin.nodeInfo.enode` 출력에 IP 가 `127.0.0.1` 로 표시될 수 있다. 상대 노드가 실제로 도달 가능한 IP (VPN/사설망 IP 등) 를 사용해야 한다. loopback 주소를 그대로 복붙하면 연결되지 않는다.

---

## 11. 검증

→ [verification.md](./verification.md)

---

## 주의사항

- `genesis/genesis.json` 은 consensus node 에서 확정 후 배포한다. rpc node 에서 독자적으로 다시 생성하지 않는다.
- 기존 datadir 가 있는 상태에서 `genesis.json` 만 교체하면 init 이 무시된다. 반드시 `clean` 후 `init` 한다.
- peer 추가 시 loopback 주소(`127.0.0.1`)는 상대 노드에서 도달 불가. 실제 도달 가능한 IP 로 교체한다.
- 현재 `STATIC_PEER_ENODE` / `static-nodes.json` 방식은 geth 1.13.15 에서 자동 연결에 실효가 없다.

---

## TODO (후속 개선)

- `static-nodes.json` 기반 방식 제거
- `config.toml` 의 `P2P.StaticNodes` 기반으로 peer 등록 자동화 → Step 10 수동 절차 제거 가능
- 문서 단순화 (자동 peer 연결 구현 후)
