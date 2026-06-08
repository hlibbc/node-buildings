# ethereum-pos-docker

Geth + Prysm 기반 Ethereum PoS private devnet — Docker Compose 2-node 구성.

Mac/Linux에서 Docker로 실험할 수 있습니다. Ubuntu 서버 배포용으로는 [ethereum-pos-native](../ethereum-pos-native)를 사용하세요.

**상태: 구현 중**

---

## 구성

| 노드 | 컨테이너 | Validator 범위 |
|------|----------|----------------|
| node0 | geth-node0, beacon-node0, validator-node0 | 0 ~ 31 |
| node1 | geth-node1, beacon-node1, validator-node1 | 32 ~ 63 |

- Chain ID: 1111
- 총 validator: 64개 (interop 모드)
- 공유 config: `./config/` (genesis.json, genesis.ssz, config.yml, jwtsecret)

---

## 전제 조건

- Docker Engine 24+ (또는 Docker Desktop)
- `pnpm` 패키지 매니저

```bash
# pnpm 설치 확인
pnpm --version

# 없으면:
# corepack enable
# corepack prepare pnpm@latest --activate
```

---

## 빠른 시작

```bash
# 1. 요구사항 확인 (Docker 설치 여부 등)
pnpm run check

# 2. env 파일 준비
cp .env.sample .env
# 이미지 버전 확인 (GETH_VERSION, PRYSM_VERSION)

# 3. 네트워크 config 생성 (최초 1회)
pnpm run generate

# 4. Geth 초기화 (최초 1회)
pnpm run init

# 5. 기동
pnpm run start

# 6. peer 연결 (첫 기동 후)
pnpm run peer:connect

# 7. finality 검증
pnpm run verify
```

---

## 포트

| 서비스 | host 포트 | 용도 |
|--------|----------|------|
| node0 HTTP RPC | 8545 | 개발 확인용 |
| node0 Beacon REST | 3500 | 개발 확인용 |
| node1 HTTP RPC | 8645 | 개발 확인용 |
| node1 Beacon REST | 3600 | 개발 확인용 |
| authrpc (8551) | **미노출** | Docker 내부 전용 |
| validator API (7000, 7500) | **미노출** | Docker 내부 전용 |

---

## 보안 정책

- **authrpc (8551)**: Docker network 내부 전용. `geth-node0:8551` 으로 beacon이 접근
- **validator API**: `127.0.0.1` 바인딩, host publish 없음
- **HTTP RPC API**: `eth,net,web3,txpool` 만 노출 (`debug`, `admin`, `personal` 제외)
- **WebSocket**: 기본 비활성 (`GETH_WS_ENABLED=true` 로 활성화)
- **이미지 버전**: `latest`/`stable` 금지 — `versions.lock` 기준, `.env`의 명시 버전 사용

---

## 파일 구조

```
ethereum-pos-docker/
├── docker-compose.yml
├── .env.sample
├── package.json
├── config/           ← 생성된 공유 config (컨테이너가 /config:ro 로 마운트)
│   ├── config.yml.example
│   └── prefund.json.example
└── scripts/
    ├── check-requirements.sh
    ├── 00-generate-config.sh   # genesis + config 생성
    ├── 01-init-geth.sh         # geth chaindata 초기화
    ├── 02-start.sh
    ├── 03-stop.sh
    ├── 04-status.sh
    ├── 05-peer-info.sh         # enode/ENR 출력
    ├── 06-peer-connect.sh      # .env 업데이트 + beacon 재시작
    ├── 07-verify.sh            # finality 검증
    └── 08-clean.sh             # 볼륨 + config 삭제
```

---

## 문서

→ [docs/ethereum-pos-docker/](../../docs/ethereum-pos-docker/README.md)
