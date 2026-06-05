# concepts.md — Ethereum PoS native devnet 동작 구조

이 문서는 Geth, Prysm beacon-chain, Prysm validator의 역할과 관계,
그리고 이 레포의 native devnet이 어떻게 동작하는지를 설명합니다.

실행 절차는 [smoke-test-node0.md](./smoke-test-node0.md)와 [native-setup.md](./native-setup.md)를 참조하세요.

---

## 1. Ethereum PoS의 3-layer 구조

현대 Ethereum은 역할이 분리된 3개의 프로세스로 동작합니다.

```
┌──────────────────────────────────────────────────────┐
│  Prysm validator                                     │
│  "이 슬롯에 나는 무엇을 서명해야 하는가?"              │
│  beacon gRPC(4000)로 beacon-chain과 통신              │
└────────────────────────┬─────────────────────────────┘
                         │ gRPC (localhost:4000)
┌────────────────────────▼─────────────────────────────┐
│  Prysm beacon-chain (CL: Consensus Layer)            │
│  "다음 블록 제안자는 누구인가? attestation 합의"       │
│  Engine API(JWT)로 Geth와 통신                        │
└────────────────────────┬─────────────────────────────┘
                         │ Engine API / JWT (localhost:8551)
┌────────────────────────▼─────────────────────────────┐
│  Geth (EL: Execution Layer)                          │
│  "트랜잭션 실행, 상태(state) 관리, 블록 바디 구성"     │
│  HTTP RPC(8545)로 외부 클라이언트와 통신              │
└──────────────────────────────────────────────────────┘
```

### 각 레이어의 역할

| 레이어 | 프로세스 | 핵심 책임 |
|--------|----------|-----------|
| Execution Layer (EL) | Geth | 트랜잭션 실행, 계정 잔액, 스마트 컨트랙트 상태 |
| Consensus Layer (CL) | Prysm beacon-chain | 블록 제안자 선정, attestation 수집, finality 결정 |
| Validator | Prysm validator | BLS 키로 블록/attestation 서명, beacon에 제출 |

---

## 2. Geth와 beacon-chain의 연결: Engine API

beacon-chain이 블록을 제안하거나 검증할 때 Geth에게 트랜잭션 실행을 위임합니다.
이 통신 채널을 **Engine API**라고 합니다.

```
beacon-chain  ──[Engine API]──▶  Geth authrpc (localhost:8551)
              payload 준비 요청
              payload 검증 요청
              forkchoice 업데이트
```

**JWT 인증**: Engine API는 외부에서 접근하면 안 되는 내부 채널입니다.
`jwtsecret` 파일(32바이트 hex)으로 양쪽이 인증합니다.
- Geth: `--authrpc.jwtsecret=/etc/ethereum-pos-native/jwtsecret`
- beacon-chain: `--jwt-secret=/etc/ethereum-pos-native/jwtsecret`

두 파일이 동일해야 연결됩니다. 이 devnet에서 **jwtsecret은 node0/node1이 동일한 파일**을 사용합니다.

**authrpc는 절대 외부에 노출하지 않습니다.** (`GETH_AUTHRPC_ADDR=127.0.0.1`)

---

## 3. beacon-chain과 validator의 연결: gRPC

validator는 beacon-chain에게 "지금 내가 해야 할 서명 작업이 있나?"를 지속적으로 묻습니다.
이 채널이 Prysm 내부 gRPC(포트 4000)입니다.

```
validator  ──[gRPC:4000]──▶  beacon-chain rpc-host (localhost:4000)
           "내 validator 차례인가?"
           "어떤 블록에 서명해야 하나?"
           서명 결과 제출
```

gRPC 포트도 내부 전용입니다. (`--rpc-host=127.0.0.1`)

외부 접근이 필요한 포트는 beacon REST API(3500)뿐입니다. 이 포트로 slot/epoch/finality를 조회합니다.

---

## 4. genesis: PoS from genesis

일반 Ethereum 메인넷은 PoW로 시작해 나중에 The Merge(PoS 전환)가 이뤄졌습니다.
이 devnet은 **처음부터 PoS로 시작**합니다.

### genesis.json의 핵심 설정

```json
"terminalTotalDifficulty": 0,
"terminalTotalDifficultyPassed": true,
"shanghaiTime": 0,
"cancunTime": 0
```

- `terminalTotalDifficulty: 0` — difficulty가 0에 도달하는 즉시 Merge 완료 상태로 간주
- `shanghaiTime: 0` — Shanghai(Capella) fork가 genesis 시점부터 활성화 (withdrawal 가능)
- `cancunTime: 0` — Cancun fork가 genesis 시점부터 활성화 (EIP-4844 blob, EIP-4788 beacon root)

genesis block의 `difficulty: "0x0"` + `terminalTotalDifficultyPassed: true` 조합이 핵심입니다.
Geth는 이 조합을 보고 "이미 Merge가 완료됐다"고 판단하며, PoW 채굴 없이 beacon-chain의 지시를 기다립니다.

### genesis.ssz: beacon chain의 초기 상태

Prysm beacon-chain은 `genesis.ssz`에서 시작 상태를 읽습니다.
이 파일에는 **64명의 validator가 미리 포함**되어 있습니다.
`prysmctl testnet generate-genesis --num-validators=64`가 이 파일을 생성합니다.

실제 체인에서는 deposit contract를 통해 validator가 등록되지만,
이 devnet은 **interop 모드**를 사용하므로 deposit 없이 미리 등록합니다.

---

## 5. config.yml: beacon chain 파라미터

beacon-chain은 체인별 파라미터를 `config.yml`에서 읽습니다.

이 devnet의 주요 값:

| 파라미터 | 값 | 의미 |
|----------|----|------|
| `SECONDS_PER_SLOT` | 12 | 슬롯 1개 = 12초 |
| `SLOTS_PER_EPOCH` | 32 | epoch 1개 = 32슬롯 = 6.4분 |
| `MIN_GENESIS_ACTIVE_VALIDATOR_COUNT` | 64 | 체인 시작에 필요한 최소 validator 수 |
| `TERMINAL_TOTAL_DIFFICULTY` | 0 | Merge 임계값 (genesis부터 PoS) |
| `DEPOSIT_CONTRACT_ADDRESS` | 0x000...0 | interop 모드: 실제 deposit contract 없음 |

### Fork 버전

모든 fork(Altair, Bellatrix, Capella, Deneb)가 **epoch 0**부터 활성화됩니다.
즉, genesis 블록부터 최신 포크 기능(withdrawal, blob 등)이 전부 작동합니다.

| Fork | Epoch | 주요 기능 |
|------|-------|-----------|
| Altair | 0 | sync committee |
| Bellatrix | 0 | The Merge, EL 연동 |
| Capella | 0 | withdrawal, BLS to execution |
| Deneb | 0 | EIP-4844 blob, EIP-4788 beacon root |

Fork 버전(0x20000089~0x20000093)은 이 devnet 전용 값으로,
mainnet/Sepolia와 구분됩니다.

---

## 6. Slot, Epoch, Finality

### Slot과 Epoch

```
epoch 0              epoch 1              epoch 2
|---- 32 slots ------|---- 32 slots ------|---- 32 slots ---...
 s0 s1 s2 ... s31    s32 s33 ... s63      s64 ...
 12s  12s  12s         각 슬롯 12초
```

- **Slot**: 블록 제안 기회. 12초마다 validator 한 명이 블록을 제안합니다.
  제안자가 오프라인이면 해당 슬롯은 건너뜁니다.
- **Epoch**: 32슬롯 묶음. epoch 경계에서 집계와 finality 계산이 이뤄집니다.

### Finality

Casper FFG 알고리즘 기준으로 2개의 연속 epoch에 2/3 이상 validator의 attestation이 모이면
이전 epoch가 **finalized** 됩니다.

```
epoch N-1 justified → epoch N justified → epoch N-1 finalized
           (2/3 attest)    (2/3 attest)
```

이 devnet(32슬롯/epoch, 12초/슬롯)에서 첫 finality까지 약 **6~12분**이 소요됩니다.

**Finality는 2/3 quorum이 필수**입니다.
validator 64명 중 node0의 32명만으로는 32/64 = 50%로 quorum 미달입니다.
**node0 + node1이 peer 연결된 상태에서만 finality가 달성됩니다.**

---

## 7. Interop 키 모드

이 devnet의 validator는 실제 ETH deposit이 아닌 **interop 키** 방식을 사용합니다.

```
validator --interop-start-index=0 --interop-num-validators=32
    → 결정론적 알고리즘으로 index 0~31의 BLS 키 자동 생성

validator --interop-start-index=32 --interop-num-validators=32
    → index 32~63의 BLS 키 자동 생성
```

같은 index에 대해 항상 동일한 키가 생성됩니다.
`genesis.ssz`도 이 알고리즘으로 같은 64개의 키를 인식하고 있으므로,
별도 키 파일 없이 validator가 즉시 active 상태가 됩니다.

### 중복 방지

같은 index를 두 validator 프로세스가 동시에 서명하면 **slashable offense**가 됩니다.
이 devnet에서 index 분리가 중요한 이유입니다:

| 노드 | VALIDATOR_START_INDEX | VALIDATOR_COUNT | 담당 범위 |
|------|-----------------------|-----------------|----------|
| node0 | 0 | 32 | 0~31 |
| node1 | 32 | 32 | 32~63 |

두 범위는 교집합이 없으므로 중복 서명이 발생하지 않습니다.

---

## 8. 2-node P2P 구조

### Geth P2P (devp2p)

Geth는 devp2p 프로토콜로 EL peer를 찾습니다.
이 devnet에서는 `STATIC_BOOTNODES`로 상대 노드를 직접 지정합니다.

```
node0 geth ←—[enode://]—→ node1 geth
           port 30303 (TCP/UDP)
           트랜잭션, 블록 바디 전파
```

peer 정보는 enode URL 형식: `enode://<pubkey>@<ip>:30303`

### Prysm Beacon P2P (libp2p)

beacon-chain은 libp2p 프로토콜로 CL peer를 찾습니다.
ENR(Ethereum Node Record)로 peer를 식별하고, `STATIC_ENRS`로 직접 지정합니다.

```
node0 beacon ←—[ENR]—→ node1 beacon
             TCP:13000 / UDP:12000
             attestation, sync committee, slot gossip 전파
```

### ENR의 IP 광고 문제

libp2p는 ENR에 이 노드의 IP를 자동 감지해서 넣습니다.
인스턴스의 인터페이스 설정에 따라 loopback(127.0.0.1)이나 0.0.0.0이 들어갈 수 있습니다.
상대 노드에서 loopback으로는 도달할 수 없으므로 peer 연결이 실패합니다.

이것이 `.env`의 `P2P_ADVERTISE_IP` 설정이 필요한 이유입니다:

```
P2P_ADVERTISE_IP=<이 인스턴스의 외부 접근 가능 IP>
```

`beacon-wrapper.sh`가 이 값을 `--p2p-host-ip` 플래그로 전달합니다.
`npm run peer:info`로 현재 광고 IP를 확인할 수 있습니다.

---

## 9. 프로세스 간 통신 전체 그림 (단일 노드)

```
                    외부 클라이언트
                         │
                   HTTP RPC :8545
                   (eth,net,web3,txpool)
                         │
         ┌───────────────▼───────────────────┐
         │         Geth (EL)                 │
         │   /var/lib/ethereum-pos-native/   │
         │   geth/geth/chaindata/            │
         └───────────────┬───────────────────┘
                         │  Engine API (JWT)
                   authrpc :8551
                   (localhost only)
                         │
         ┌───────────────▼───────────────────┐
         │    Prysm beacon-chain (CL)        │
         │  /var/lib/ethereum-pos-native/    │
         │  prysm-beacon/beaconchaindata/    │
         │                                   │
         │  REST API :3500 (slot/epoch 조회) │
         │  P2P TCP:13000 / UDP:12000        │
         └───────────────┬───────────────────┘
                         │  gRPC (localhost:4000)
                         │
         ┌───────────────▼───────────────────┐
         │    Prysm validator                │
         │  /var/lib/ethereum-pos-native/    │
         │  prysm-validator/                 │
         │  interop keys: index 0~31 (node0) │
         └───────────────────────────────────┘
```

---

## 10. 공유 config 파일 구조

node0/node1이 **반드시 동일한 파일**을 사용해야 합니다.

| 파일 | 위치 | 공유 대상 | 재생성 가능 여부 |
|------|------|-----------|-----------------|
| `genesis.json` | `/etc/ethereum-pos-native/` | 모든 노드 | 아니오 (재생성 시 다른 체인) |
| `genesis.ssz` | `/etc/ethereum-pos-native/` | 모든 노드 | 아니오 (재생성 시 validator 불일치) |
| `config.yml` | `/etc/ethereum-pos-native/` | 모든 노드 | 아니오 (fork 파라미터 변경 불가) |
| `jwtsecret` | `/etc/ethereum-pos-native/` | 모든 노드 | 재생성 시 모든 노드 동기화 필요 |

`02-generate-network-config.sh`는 **node0에서 1회만** 실행합니다.
node1에는 `scp`로 복사합니다.

---

## 11. OffchainLabs/prysm을 사용하는 이유

이 devnet은 추후 Arbitrum Orbit L2의 L1 parent chain으로 사용될 예정입니다.
Arbitrum Nitro는 Ethereum PoS L1과 특정 인터페이스(EIP-4788 beacon root 조회 등)로 통신합니다.

`OffchainLabs/prysm`은 prysmaticlabs/prysm의 fork로,
Arbitrum 생태계와의 호환성 검증이 이뤄진 빌드를 제공합니다.

기본값: `PRYSM_GITHUB_ORG=OffchainLabs`
upstream 전환: `PRYSM_GITHUB_ORG=prysmaticlabs sudo npm run install:prysm`

---

## 참고

| 문서 | 내용 |
|------|------|
| [smoke-test-node0.md](./smoke-test-node0.md) | node0 단독 기동 확인 절차 |
| [native-setup.md](./native-setup.md) | 전체 2-node 구축 절차 |
| [peer-connection.md](./peer-connection.md) | Geth/Prysm peer 연결 및 P2P_ADVERTISE_IP |
| [finality-check.md](./finality-check.md) | finality 검증 명령 및 모드 |
| [rpc-security.md](./rpc-security.md) | 포트 보안, systemd 권한, WS/authrpc 정책 |
| [version-matrix.md](./version-matrix.md) | 버전 기록, 미검증 항목 |
