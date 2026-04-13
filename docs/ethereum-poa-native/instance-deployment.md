# ethereum-poa-native 인스턴스 구축

geth 1.13.15 Clique PoA 테스트망을 두 인스턴스(consensus / rpc)에 구축하는 절차.

---

## 사전 준비

- 인스턴스 2개 (consensus, rpc) — 단일 머신 테스트도 가능 (포트 분리 필요)
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

최소 설정값:

```dotenv
CHAIN_ID=12345
NETWORK_ID=                        # 비워두면 CHAIN_ID 사용

CONFIG_DIR=/opt/eth/consensus/config
BACKUP_DIR=/opt/eth/consensus/backup
EXECUTION_ROOT=/opt/eth/consensus
PASSWORD_ROOT=/opt/eth/consensus/config/password.txt

GETH_PORT=30303
GETH_HTTP_PORT=8545
GETH_WS_PORT=8546

CONSENSUS_HTTP_ADDR=127.0.0.1      # 외부 공개 금지
MINER_ADDRESS=                     # generate 실행 후 자동 기록됨
```

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
// "enode://<pubkey>@127.0.0.1:30303"
```

> **중요:** `127.0.0.1` 부분을 consensus 인스턴스의 실제 IP로 교체해서 rpc env에 입력

---

## 7. rpc 인스턴스 — env 준비

```bash
cp .env_sample rpc.env
```

최소 설정값:

```dotenv
CHAIN_ID=12345                     # consensus 와 동일
NETWORK_ID=                        # 비워두면 CHAIN_ID 사용

CONFIG_DIR=/opt/eth/rpc/config
BACKUP_DIR=/opt/eth/rpc/backup
EXECUTION_ROOT=/opt/eth/rpc        # consensus 와 다른 경로
PASSWORD_ROOT=/opt/eth/rpc/config/password.txt

GETH_PORT=30304                    # consensus 와 다른 포트 (단일 머신 시)
GETH_HTTP_PORT=8645
GETH_WS_PORT=8646

STATIC_PEER_ENODE=enode://<pubkey>@<consensus-ip>:30303
```

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
