# ethereum-poa-native 인스턴스 구축

geth 1.13.15 Clique PoA 테스트망을 두 인스턴스(consensus / rpc)에 구축하는 절차.

---

## 사전 준비

- consensus 인스턴스 1대 + rpc 인스턴스 1대
- 각 인스턴스에 `jq`, `node` 설치
- geth 바이너리는 레포에 포함: `projects/ethereum-poa-native/geth/v1.13.15/geth`

---

## 1. 레포 클론

```bash
git clone <repo-url>
cd node-buildings/projects/ethereum-poa-native
```

---

## 2. consensus 인스턴스 — env 준비

```bash
cp .env_sample consensus.env
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

CONSENSUS_HTTP_ADDR=127.0.0.1      # 외부 공개 금지
MINER_ADDRESS=                     # generate 실행 후 자동 기록됨
```

> 운영 환경에서는 `/opt/eth/consensus/...` 등 절대경로로 변경.

---

## 3. consensus — miner 계정 생성

```bash
./setup.sh --env=consensus.env generate
```

- 무작위 패스워드 생성 → `PASSWORD_ROOT` 경로에 저장
- miner 계정 생성 → `MINER_ADDRESS` 가 `consensus.env` 에 자동 기록
- genesis `extradata` 갱신

---

## 4. consensus — genesis 초기화

```bash
./setup.sh --env=consensus.env init
```

- `CHAIN_ID` 값이 `genesis.json config.chainId` 에 주입되어 초기화

---

## 5. consensus — 노드 실행

```bash
./setup.sh --env=consensus.env run-consensus
```

- 로그: `tail -f geth.log`
- 상태: `./setup.sh --env=consensus.env status`

---

## 6. consensus enode 확인

IPC로 접속:

```bash
./setup.sh --env=consensus.env attach
```

```javascript
admin.nodeInfo.enode
// "enode://<pubkey>@<consensus-ip>:30303"
```

> 출력된 enode의 IP가 `127.0.0.1` 이면 consensus 인스턴스의 실제 IP로 교체한다. 이 값을 그대로 `STATIC_PEER_ENODE` 에 입력.

---

## 7. rpc 인스턴스 — env 준비

```bash
cp .env_sample rpc.env
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

# 6단계에서 확인한 enode URL (IP를 consensus 실제 IP로 교체한 값)
STATIC_PEER_ENODE=enode://<pubkey>@<consensus-ip>:30303
```

> `PASSWORD_ROOT` 는 rpc 노드에서 사용하지 않으므로 생략.

---

## 8. rpc — genesis 초기화

```bash
./setup-rpc-node.sh --env=rpc.env init
```

---

## 9. rpc — 노드 실행

```bash
./setup-rpc-node.sh --env=rpc.env run
```

- 로그: `tail -f geth-rpc.log`
- 상태: `./setup-rpc-node.sh --env=rpc.env status`

---

## 10. 검증

→ [verification.md](./verification.md)
