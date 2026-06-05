# native-setup.md — 단계별 구축 절차

Geth + Prysm native 2-node PoS devnet 구축 절차.
각 명령은 `projects/ethereum-pos-native/` 디렉토리에서 실행합니다.

---

## 전제 조건

- Ubuntu 22.04+ 또는 Debian 12+ (Linux amd64 / arm64)
- 2개 인스턴스: node0, node1
- 각 인스턴스에서 root 또는 sudo 권한
- 필수 패키지: `curl`, `jq`, `openssl`, `coreutils`, `systemd`

```bash
apt-get update && apt-get install -y curl jq openssl
```

---

## 단계 1 — 요구사항 확인 (양쪽 노드)

```bash
npm run check
```

출력에 `[MISSING]` 항목이 없어야 합니다.

---

## 단계 2 — Geth / Prysm 설치 (양쪽 노드)

```bash
sudo npm run install:geth
sudo npm run install:prysm
```

**Geth 설치 방식: 공식 apt repository**

- 저장소: `ppa:ethereum/ethereum` (Ethereum Foundation 공식 PPA)
- 검증: GPG 서명 자동 검증 (key: 8A16544F), 비공식 바이너리 설치 금지
- Ubuntu 22.04+: `add-apt-repository` 방식
- Debian 12+: 수동 PPA 설정 방식
- 설치 후 `apt-mark hold geth` 적용 (accidental upgrade 방지)

설치 경로:
- `/usr/bin/geth` (apt 관리)
- `/usr/local/bin/geth` → `/usr/bin/geth` (symlink, TASK.md 경로 준수)
- `/usr/local/bin/beacon-chain`
- `/usr/local/bin/validator`
- `/usr/local/bin/prysmctl`

**Prysm 설치 방식: 공식 GitHub release binary**

- 저장소: `https://github.com/prysmaticlabs/prysm/releases`
- 검증: `checksums.txt` SHA256 검증 (asset basename 기준)

설치 후 `versions.lock`에 버전 정보가 기록됩니다:
```bash
cat projects/ethereum-pos-native/versions.lock
apt-cache policy geth   # Geth apt 설치 상세 정보
```

---

## 단계 3 — env 파일 준비 (각 노드에서)

**node0:**
```bash
cp .env.node0.sample .env
```

편집 필요 항목:
```dotenv
NODE0_HOST=<node0의 실제 IP>
NODE1_HOST=<node1의 실제 IP>
FEE_RECIPIENT=<fee 수령 주소, devnet은 0x0000...0000 가능>
```

**node1:**
```bash
cp .env.node1.sample .env
```

편집 필요 항목: 동일 (NODE0_HOST, NODE1_HOST, FEE_RECIPIENT)

---

## 단계 4 — prefunded 계정 설정 (선택, node0에서)

Arbitrum L2 deployer 등 초기 잔액이 필요한 주소:

```bash
cp config/prefund.json.example config/prefund.json
# address 필드를 실제 deployer 주소로 교체
```

`config/prefund.json`이 없으면 빈 alloc으로 genesis가 생성됩니다.

---

## 단계 5 — 네트워크 config 생성 (node0에서만 1회)

```bash
sudo npm run generate
```

생성 파일 (`/etc/ethereum-pos-native/`):
- `genesis.json` — Geth genesis block (prysmctl이 최종 수정)
- `genesis.ssz` — Prysm beacon genesis state (validator 64개 포함)
- `config.yml` — Prysm beacon 설정
- `jwtsecret` — Engine API JWT secret

> 이 명령은 node0에서만 실행합니다. node1에서 재실행하면 오류로 중단됩니다.

---

## 단계 6 — node1에 config 복사

**node0에서 실행:**
```bash
# /etc/ethereum-pos-native/ 전체를 node1에 복사
scp -r /etc/ethereum-pos-native/ <node1-user>@<node1-ip>:/etc/

# 복사 확인 (양쪽에서 실행, SHA256 일치 여부)
sha256sum /etc/ethereum-pos-native/genesis.ssz
sha256sum /etc/ethereum-pos-native/jwtsecret
```

> 복사 전에 node1에서 먼저 `/etc/ethereum-pos-native/` 디렉토리를 삭제하거나 없는 상태여야 합니다.

---

## 단계 7 — Geth 초기화 (양쪽 노드에서)

```bash
sudo npm run init
```

- `/var/lib/ethereum-pos-native/geth/geth/chaindata` 생성
- 양쪽 노드에서 동일한 genesis.json으로 초기화해야 합니다
- genesis.json 검증 (SHA256):

```bash
jq -S . /etc/ethereum-pos-native/genesis.json | sha256sum
# 양쪽 노드에서 동일한 값이 나와야 합니다
```

---

## 단계 8 — systemd 서비스 설치 (양쪽 노드에서)

```bash
sudo npm run install:services
```

설치 결과:
- `/etc/systemd/system/eth-pos-geth-<NODE_NAME>.service`
- `/etc/systemd/system/eth-pos-beacon-<NODE_NAME>.service`
- `/etc/systemd/system/eth-pos-validator-<NODE_NAME>.service`
- `/etc/ethereum-pos-native/<NODE_NAME>.env`

---

## 단계 9 — 노드 시작 (양쪽 노드에서)

```bash
sudo npm run start
```

시작 순서: geth → beacon → validator

서비스 상태 확인:
```bash
sudo npm run status
```

로그 확인:
```bash
journalctl -u eth-pos-geth-eth-pos-node0 -f
journalctl -u eth-pos-beacon-eth-pos-node0 -f
```

---

## 단계 10 — peer 연결

첫 시작 후 양쪽 노드가 서로를 발견하도록 peer 정보를 교환합니다.

→ **[peer-connection.md](./peer-connection.md)**

peer 연결 없이는 finality를 달성할 수 없습니다.

---

## 단계 11 — finality 검증

```bash
npm run verify
```

→ **[finality-check.md](./finality-check.md)**

기대 결과:
- `eth_blockNumber` 증가
- slot / epoch 진행
- `finalized epoch > 0`
- validator active 상태

---

## 재시작 절차

```bash
sudo npm run stop
sudo npm run start
```

재시작 후 확인:
- block number가 정지 이전 값보다 크거나 같아야 함
- `/var/lib/ethereum-pos-native/geth/geth/chaindata` 존재해야 함
- finality checkpoint가 이어져야 함

---

## 데이터 경로 요약

| 경로 | 내용 | 재시작 시 |
|------|------|-----------|
| `/etc/ethereum-pos-native/` | genesis, config, jwtsecret | 보존 (삭제 금지) |
| `/var/lib/ethereum-pos-native/geth/` | Geth 체인 데이터 | 보존 |
| `/var/lib/ethereum-pos-native/prysm-beacon/` | Beacon 체인 데이터 | 보존 |
| `/var/lib/ethereum-pos-native/prysm-validator/` | Validator 데이터 | 보존 |
| `/var/log/ethereum-pos-native/` | 로그 파일 | 보존 (롤링) |
