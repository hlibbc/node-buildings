# setup.md — Docker Compose 구축 절차

`projects/ethereum-pos-docker/` 디렉토리에서 실행합니다.

---

## 전제 조건

- Docker Engine 24+ (또는 Docker Desktop)
- `docker compose` plugin (v2)
- `pnpm` (패키지 매니저)
- `curl`, `jq`, `openssl`

### pnpm 확인

```bash
pnpm --version
```

pnpm이 없으면 corepack으로 설치:

```bash
corepack enable
corepack prepare pnpm@latest --activate
pnpm --version
```

### Docker 확인

```bash
docker --version
docker compose version
docker info | grep -E "CPUs|Total Memory|Architecture"
```

### 요구사항 자동 점검

```bash
pnpm run check
```

---

## 단계 1 — env 준비

```bash
cp .env.sample .env
```

확인 필수 항목:

```dotenv
# 이미지 버전 — latest/stable 금지, 명시 버전 유지
GETH_VERSION=v1.14.12
PRYSM_VERSION=v5.3.2

# Chain
CHAIN_ID=1111
NETWORK_ID=1111

# Host 포트 (충돌 시 변경)
NODE0_RPC_PORT=8545
NODE0_BEACON_PORT=3500
NODE1_RPC_PORT=8645
NODE1_BEACON_PORT=3600
```

---

## 단계 2 — genesis / config 생성 (최초 1회)

```bash
pnpm run generate
```

처리 순서:
1. `./config/jwtsecret` 생성 (openssl)
2. `./config/genesis.json` 생성 (jq 템플릿)
3. `./config/config.yml` 생성 (beacon chain 파라미터)
4. `create-genesis` 컨테이너 실행 → `./config/genesis.ssz` 생성

> **NOTE**: prysmctl `--fork=deneb` 지원 여부는 Prysm 버전에 따라 다릅니다.
> 실패 시 troubleshooting 섹션 참조.

genesis 파일은 모든 컨테이너가 공유합니다:

```
./config/
  genesis.json  ← geth init, beacon에서 사용
  genesis.ssz   ← beacon genesis state (64 validators pre-loaded)
  config.yml    ← beacon 파라미터 (fork version, slot 설정 등)
  jwtsecret     ← Engine API JWT 인증 (geth ↔ beacon)
```

---

## 단계 3 — Geth 초기화 (최초 1회)

```bash
pnpm run init
```

- `geth-init-node0`, `geth-init-node1` 컨테이너가 순서대로 실행
- `genesis.json`으로 각 노드의 Docker 볼륨 초기화

---

## 단계 4 — 서비스 기동

```bash
pnpm run start
```

6개 컨테이너가 시작됩니다:
```
geth-node0, beacon-node0, validator-node0
geth-node1, beacon-node1, validator-node1
```

상태 확인:
```bash
pnpm run status
# 또는
docker compose ps
docker compose logs -f beacon-node0
```

---

## 단계 5 — peer 연결

첫 기동 후 두 노드가 서로를 찾을 수 있도록 peer 정보를 교환합니다.

```bash
# 현재 peer 정보 확인
pnpm run peer:info

# 자동 연결 (enode/ENR 조회 → .env 업데이트 → beacon 재생성)
pnpm run peer:connect
```

`peer:connect` 처리 내용:
1. Geth enode 조회 (`docker exec geth attach`)
2. Beacon ENR 조회 (REST API)
3. `.env` 업데이트 (`GETH_NODE*_ENODE`, `BEACON_NODE*_ENR`)
4. `docker exec geth attach admin.addPeer(...)` (Geth 즉시 적용)
5. `docker compose up -d --force-recreate --no-deps beacon-node0 beacon-node1` (beacon 재생성)

> **주의사항**
> - `.env` 변경값은 기존 실행 중인 컨테이너에 자동 반영되지 않습니다.
> - Beacon `--bootstrap-node` 반영은 컨테이너 재생성(`--force-recreate`)이 필요합니다.
>   (`docker compose restart` 는 기존 컨테이너를 그대로 재시작하므로 환경변수를 새로 읽지 않습니다.)
> - Geth peer 는 `admin.addPeer(...)` 로 즉시 추가되며, `.env` 의 `GETH_NODE*_ENODE` 값은 다음 재생성/재기동 시 `--bootnodes` 로 반영됩니다.

---

## 단계 6 — finality 검증

peer 연결 후 약 6~12분 후:

```bash
# 최종 검증 (peer≥1, finalized epoch>0 필요)
pnpm run verify

# 기동 직후 확인 (peer=0, finality=0 WARN으로 처리)
pnpm run verify -- --allow-waiting
```

기대 결과:
- Geth blockNumber 증가
- beacon slot/epoch 진행
- finalized epoch > 0
- validator[0] / validator[32] status = `active_ongoing`

---

## 포트 정책

| 서비스 | host 포트 | container 포트 | 설명 |
|--------|----------|----------------|------|
| node0 HTTP RPC | `NODE0_RPC_PORT` (8545) | 8545 | 개발 확인용 |
| node0 Beacon REST | `NODE0_BEACON_PORT` (3500) | 3500 | 개발 확인용 |
| node0 Geth P2P | `NODE0_GETH_P2P_PORT` (30303) | 30303 | P2P |
| node0 Beacon P2P | `NODE0_BEACON_P2P_TCP` (13000) | 13000 | P2P |
| node1 HTTP RPC | `NODE1_RPC_PORT` (8645) | 8545 | 개발 확인용 |
| node1 Beacon REST | `NODE1_BEACON_PORT` (3600) | 3500 | 개발 확인용 |
| **authrpc (8551)** | **미노출** | 8551 | Docker 내부 전용 |
| **validator API** | **미노출** | 7000, 7500 | Docker 내부 전용 |

---

## WebSocket 활성화 (선택)

기본값 `GETH_WS_ENABLED=false`. 활성화:

```dotenv
# .env
GETH_WS_ENABLED=true
```

```bash
# 서비스 재시작으로 반영
pnpm run stop && pnpm run start
```

---

## Troubleshooting

### fork version이 mainnet config와 충돌 시

**증상**:

```
FATA Could not generate beacon chain genesis state
error="could not set config params: version 0x05000000 for fork electra in config eth-pos-devnet
       conflicts with existing config named=mainnet"
```

또는 `fulu` / 다른 fork 이름으로 같은 패턴의 오류.

**원인**: `config.yml`에 해당 fork version이 없어서 Prysm이 mainnet 기본값(예: Electra=`0x05000000`, Fulu=`0x06000000`)을 보충하고, 기존에 등록된 mainnet config와 충돌.

**해결**: `00-generate-config.sh`에서 충돌 fork를 devnet 전용 계열(`0x200000xx`)로 명시하고 epoch을 far future로 설정한 뒤 재생성.

현재 적용된 devnet fork version 계열:

| Fork | Version | Epoch |
|------|---------|-------|
| Genesis | 0x20000089 | — |
| Altair | 0x20000090 | 0 |
| Bellatrix | 0x20000091 | 0 |
| Capella | 0x20000092 | 0 |
| Deneb | 0x20000093 | 0 (genesis 기준) |
| Electra | 0x20000094 | far future (비활성) |
| Fulu | 0x20000095 | far future (비활성) |

```bash
# 재생성
pnpm run clean
pnpm run generate
grep -n "FORK" config/config.yml   # 전체 fork 항목 확인
```

> **NOTE**: Prysm 버전 업그레이드 시 새 fork가 추가될 수 있습니다.
> 같은 패턴의 오류가 재발하면 충돌하는 fork version을 `0x200000xx` 계열로 추가하고 epoch을 `18446744073709551615`로 설정하세요.

### beacon-node0/1 시작 실패: `/bin/sh: no such file`

**증상**:

```
exec: "/bin/sh": stat /bin/sh: no such file or directory
```

**원인**: Prysm beacon-chain 이미지(`gcr.io/prysmaticlabs/prysm/beacon-chain`)에는 `/bin/sh`가 없습니다. `docker-compose.yml`에서 `entrypoint: ["/bin/sh", "-c"]` 방식을 사용하면 이미지의 기본 entrypoint(`/beacon-chain`)가 override되고 shell이 없어서 실행에 실패합니다.

**해결**: beacon-chain은 shell 없이 command list 방식으로 직접 실행합니다. `--bootstrap-node`는 peer:connect 이후 `docker-compose.peer.yml` override로 반영합니다.

- 최초 기동(`pnpm run start`): `docker-compose.yml`만 사용 — bootstrap-node 없이 기동
- peer 연결(`pnpm run peer:connect`): `docker-compose.peer.yml` overlay로 beacon 재생성 — `--bootstrap-node` 포함

### `--fork=deneb` 실패 시

`pnpm run generate` 중 `create-genesis` 컨테이너가 실패하면:

```bash
docker compose logs create-genesis
```

- Prysm 버전이 `--fork=deneb`을 지원하지 않으면 `--fork=capella`로 변경:
  `scripts/00-generate-config.sh`의 `--fork=deneb` 부분을 수정

### Geth init 실패

```bash
docker compose --profile init logs geth-init-node0
```

- `genesis.json`이 없으면 `pnpm run generate` 재실행

### beacon health 503

```bash
docker compose logs beacon-node0
```

- geth authrpc 연결 실패: `geth-node0` 실행 중인지 확인
- jwtsecret 불일치: `./config/jwtsecret` 내용 확인 (모든 노드 동일해야 함)

### 데이터 초기화

```bash
pnpm run clean   # 볼륨 + config 파일 전체 삭제
pnpm run generate && pnpm run init && pnpm run start
```

---

## Mac에서 공유/압축 전 AppleDouble 메타데이터 제거

Mac은 파일 시스템 작업 중 `._*` (AppleDouble) 및 `.DS_Store` 메타데이터 파일을 생성합니다.
프로젝트를 타인에게 전달하거나 git commit 전에 아래 명령으로 제거하세요.

```bash
# 프로젝트 루트에서 실행
find . -name '._*' -delete
find . -name '.DS_Store' -delete
```

> 이 파일들은 루트 `.gitignore`에 이미 포함되어 있으나,
> Docker volume 마운트(`./config/`) 내부에 생성된 경우 컨테이너가 인식하지 못하도록 삭제를 권장합니다.

---

## 최종 실행 순서 (전체 흐름)

처음부터 finality 달성까지 순서대로 실행하는 참조용 스크립트입니다.

```bash
cd projects/ethereum-pos-docker

# 기존 데이터/볼륨 전체 초기화 (재시작 시)
pnpm run clean

# env 파일 준비
rm -f .env
cp .env.sample .env

# Compose 파일 유효성 확인
docker compose --env-file .env config

# genesis / config 생성 (최초 1회)
pnpm run generate
ls -al config

# Geth 초기화 (최초 1회)
pnpm run init

# 서비스 기동
pnpm run start
pnpm run status

# peer 연결 (첫 기동 후)
pnpm run peer:connect

# 기동 직후 확인 (peer/finality 미달성은 WARN)
pnpm run verify -- --allow-waiting

# finality 달성 대기 (약 13분)
sleep 780

# 최종 검증 (FAIL=0 이어야 성공)
pnpm run verify
```
