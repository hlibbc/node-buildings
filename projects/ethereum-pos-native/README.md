# ethereum-pos-native

최신 Geth + Prysm 기반 Ethereum PoS private devnet — native 2-node 구성.
Arbitrum L2 parent chain 준비용.

**상태: 구현 중**

---

## 구성

| 노드 | 역할 | Validator 범위 |
|------|------|----------------|
| `eth-pos-node0` | Geth + Prysm beacon + Prysm validator | 0 ~ 31 |
| `eth-pos-node1` | Geth + Prysm beacon + Prysm validator | 32 ~ 63 |

- 총 validator: 64개 (interop 모드, 결정론적 BLS 키)
- Chain ID: 1111
- Fork: Cancun/Deneb (genesis부터 활성화)
- 블록 타임: 12초 / epoch: 32 slot

---

## 빠른 시작

### 전제 조건

- Ubuntu 22.04+ / Debian 12+ (Linux amd64 또는 arm64)
- `curl`, `jq`, `openssl`, `sha256sum`, `systemctl` 설치
- sudo 또는 root 권한

### node0 설정

```bash
# 1. 요구사항 확인
npm run check

# 2. 바이너리 설치
sudo npm run install:geth
sudo npm run install:prysm

# 3. env 파일 준비
cp .env.node0.sample .env
# NODE0_HOST, NODE1_HOST, FEE_RECIPIENT 설정

# 4. 네트워크 config 생성 (node0에서만 1회)
sudo npm run generate

# 5. Geth 초기화
sudo npm run init

# 6. systemd 서비스 설치
sudo npm run install:services

# 7. 노드 시작
sudo npm run start
```

### node1 설정

```bash
# node0에서 config 복사
scp -r /etc/ethereum-pos-native/ <node1-user>@<node1-host>:/etc/

# node1에서
cp .env.node1.sample .env
# NODE0_HOST, NODE1_HOST 설정

sudo npm run install:geth
sudo npm run install:prysm
sudo npm run init
sudo npm run install:services
sudo npm run start
```

### peer 연결

첫 기동 후 상대 노드의 enode/ENR을 확인하고 env를 업데이트합니다.
→ [docs/ethereum-pos-native/peer-connection.md](../../docs/ethereum-pos-native/peer-connection.md)

### finality 검증

```bash
npm run verify
```

---

## 파일 구조

```
ethereum-pos-native/
├── .env.node0.sample          # node0 env 예제
├── .env.node1.sample          # node1 env 예제
├── versions.lock              # 설치된 버전 (설치 스크립트가 기록)
├── config/                    # 설정 예제
│   ├── config.yml.example
│   ├── prefund.json.example
│   └── jwtsecret.example
├── scripts/
│   ├── common/                # 공통 유틸리티
│   └── native/                # 설치 및 운영 스크립트
│       ├── 00-install-geth.sh
│       ├── 01-install-prysm.sh
│       ├── 02-generate-network-config.sh  # node0 1회 실행
│       ├── 03-init-geth.sh
│       ├── 04-install-systemd-services.sh
│       ├── 05-start-node.sh
│       ├── 06-stop-node.sh
│       ├── 07-status-node.sh
│       ├── 08-clean-node.sh
│       └── 09-verify-finality.sh
└── systemd/                   # service 템플릿
```

---

## 문서

→ [docs/ethereum-pos-native/](../../docs/ethereum-pos-native/README.md)

---

## 주의사항

- `02-generate-network-config.sh`는 node0에서만 실행. node1에 scp 복사.
- 각 노드의 validator index 범위가 겹치면 slashing 발생.
- `CONFIG_ROOT=/etc/ethereum-pos-native` 는 공유 config 디렉토리 (clean 시 삭제 금지).
- Docker 방식은 Native 안정화 후 검토 예정 → [docker-plan.md](../../docs/ethereum-pos-native/docker-plan.md)
