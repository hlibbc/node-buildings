# nitro-testnode 분석 보고서

`references/nitro-testnode`를 분석하여 `projects/arbitrum-l2-docker` 구현에 필요한 내용을 정리한 문서입니다.

분석 대상 파일:
- `references/nitro-testnode/test-node.bash`
- `references/nitro-testnode/docker-compose.yaml`
- `references/nitro-testnode/scripts/config.ts`
- `references/nitro-testnode/scripts/index.ts`
- `references/nitro-testnode/scripts/ethcommands.ts`
- `references/nitro-testnode/rollupcreator/Dockerfile`
- `references/nitro-testnode/scripts/Dockerfile`

---

## 1. 내장 L1 geth 의존 지점

`nitro-testnode`는 L1을 내장 geth(`--dev` 모드)로 운용한다고 가정하고 설계되어 있다. 의존 지점은 다음과 같다.

- `test-node.bash:60` — `l1chainid=1337` 하드코딩
- `test-node.bash:561` — rollupcreator 실행 시 `PARENT_CHAIN_RPC="http://geth:8545"` 하드코딩
- `docker-compose.yaml` — `sequencer` depends_on `geth`
- `docker-compose.yaml` — `poster` depends_on `geth, redis`
- `docker-compose.yaml` — `rollupcreator` depends_on `geth, sequencer`
- `docker-compose.yaml` — `tokenbridge` 환경변수 `ETH_URL=http://geth:8545`
- `scripts/index.ts:55` — `argv.l1url` 기본값 `"ws://geth:8546"`
- `scripts/config.ts` — `parent-chain.connection.url: argv.l1url` (sequencer_config.json에 기록됨)
- `l1keystore` Docker volume — geth 내장 named account 키를 sequencer/poster/rollupcreator가 공유

geth 서비스 자체는 `--dev --dev.period=1` 모드(자동 채굴 + 내장 keystore)로 동작하며,
이 keystore에 sequencer, poster, validator 등의 키가 저장되어 있다.
우리 구현에서는 이 keystore를 `.env` private key로 완전히 대체한다.

---

## 2. 외부 L1 RPC/WS로 치환해야 하는 지점

| 치환 전 | 치환 후 |
|---------|---------|
| `"http://geth:8545"` | `PARENT_CHAIN_RPC` (l1-chain-info.json 또는 .env override) |
| `"ws://geth:8546"` | `PARENT_CHAIN_WS` (동일) |
| `l1chainid=1337` | l1-chain-info.json의 `chainId` 필드 |
| `depends_on: geth` | 제거 (외부 L1이므로 불필요) |
| `l1keystore` volume (geth 내장 키) | `.env`의 `L2_*_PRIVATE_KEY` 로 대체 |
| `namedAccount("sequencer")` 방식 | private key 직접 사용 방식으로 대체 |

`write-config`(scripts 서비스)에서 `argv.l1url`을 받아 `sequencer_config.json`의
`parent-chain.connection.url`에 기록하는 구조이므로,
이 값에 외부 WS URL(`PARENT_CHAIN_WS`)을 넣으면 된다.

---

## 3. rollupcreator create-rollup-testnode 실행에 필요한 env 목록

`rollupcreator/Dockerfile`은 `nitro-contracts` 저장소를 클론하여 빌드하며,
`ENTRYPOINT ["yarn"]`으로 `yarn create-rollup-testnode`를 실행한다.

### 필수 환경변수

```
PARENT_CHAIN_RPC=           # L1 HTTP RPC URL
DEPLOYER_PRIVKEY=           # L2 deployer private key
PARENT_CHAIN_ID=            # L1 chain ID (예: 1111)
CHILD_CHAIN_NAME=           # L2 chain 이름 (예: "l2konet-dev")
OWNER_ADDRESS=              # L2 rollup owner address
WASM_MODULE_ROOT=           # nitro-node 컨테이너에서 추출 (아래 참조)
SEQUENCER_ADDRESS=          # L2 sequencer address
CHILD_CHAIN_CONFIG_PATH=    # 입력: /config/l2_chain_config.json
CHAIN_DEPLOYMENT_INFO=      # 출력: /config/deployment.json
CHILD_CHAIN_INFO=           # 출력: /config/deployed_chain_info.json
```

### 고정 가능한 환경변수

```
MAX_DATA_SIZE=117964        # 기본값 그대로 사용 가능
AUTHORIZE_VALIDATORS=10     # 기본값 그대로 사용 가능
```

### WASM_MODULE_ROOT 추출 방법

WASM_MODULE_ROOT는 실제 L2 sequencer 서비스를 start하기 전에 추출한다.
nitro-node 이미지를 임시 컨테이너로 실행하여 파일을 읽는 방식이며, L2 서비스 기동과는 별개의 단계다.

```bash
wasmroot=$(docker compose run --rm --entrypoint sh sequencer \
    -c "cat /home/user/target/machines/latest/module-root.txt")
```

**중요:** 이 명령은 sequencer 서비스를 start하는 것이 아니라, nitro-node 이미지에서 wasm root 값을 읽기 위한 임시 실행이다. rollupcreator 실행 전, `05-start-l2.sh` 이전 단계에서 수행한다.

---

## 4. l2_chain_config.json / deployed_chain_info.json / l2_chain_info.json 생성 흐름

```
[02-render-chain-config 단계]
  scripts/config.ts의 write-l2-chain-config 로직 재현
  → /config/l2_chain_config.json
    {
      chainId: L2_CHAIN_ID,
      homesteadBlock: 0, ...,
      arbitrum: {
        EnableArbOS: true,
        AllowDebugPrecompiles: true,
        DataAvailabilityCommittee: false,
        InitialArbOSVersion: 40,
        InitialChainOwner: L2_ROLLUP_OWNER_ADDRESS,
        GenesisBlockNum: 0
      }
    }

[03-deploy-rollup 단계]
  docker compose run --rm rollupcreator create-rollup-testnode
  읽음: /config/l2_chain_config.json  ← CHILD_CHAIN_CONFIG_PATH
  씀:   /config/deployment.json       ← CHAIN_DEPLOYMENT_INFO
        /config/deployed_chain_info.json  ← CHILD_CHAIN_INFO

  deployment.json에는 rollup, bridge, inbox, outbox,
  sequencerInbox, rollupEventInbox 컨트랙트 주소가 들어 있음.

[03-deploy-rollup 단계 후처리]
  docker compose run --rm --entrypoint sh rollupcreator \
      -c "jq [.[]] /config/deployed_chain_info.json > /config/l2_chain_info.json"

  l2_chain_info.json = deployed_chain_info.json을 배열로 감싼 것
  (추가 변환 없음, timeboost 미사용 기준)

[04-render-node-configs 단계]
  scripts/config.ts의 write-config 로직 재현
  읽음: /config/l2_chain_info.json  (chain.info-files 경로로 참조)
  씀:   /config/sequencer_config.json
        /config/validation_node_config.json
```

---

## 5. sequencer가 l2_chain_info.json을 참조하는 방식

`scripts/config.ts`에서 `write-config` 실행 시 다음 구조로 기록된다:

```typescript
const chainInfoFile = path.join(consts.configpath, "l2_chain_info.json")
// sequencer_config.json에 삽입:
{
  "chain": {
    "id": 412346,
    "info-files": ["/config/l2_chain_info.json"]
  }
}
```

sequencer(`/usr/local/bin/nitro`) 기동 시 `--conf.file=/config/sequencer_config.json`으로
이 파일을 읽고, `chain.info-files`에 적힌 경로에서 다음을 로드한다:

- rollup 컨트랙트 주소
- chain ID
- sequencer inbox 주소
- bridge 주소

**이 파일이 없거나 경로가 잘못되면 sequencer가 기동하지 않는다.**

`l2_chain_info.json`은 rollup 배포 후에야 존재하므로, node config 렌더링은 반드시 rollup 배포 이후에 실행해야 한다. 구현 스크립트는 이 의존 관계를 반영하여 세 단계로 분리한다.

실제 순서:
1. `02-render-chain-config` — l2_chain_config.json 생성 (rollupcreator 입력용)
2. `03-deploy-rollup` — deployed_chain_info.json + l2_chain_info.json 생성
3. `04-render-node-configs` — l2_chain_info.json을 읽어 sequencer_config.json 생성

---

## 6. L1 → L2 ETH deposit 구현 후보

### ethcommands.ts bridgeFunds 분석

```typescript
// deployment.json에서 inbox 주소 추출
const deploydata = JSON.parse(fs.readFileSync(".../deployment.json"))
const inboxAddr = ethers.utils.hexlify(deploydata.inbox)

// Inbox.depositEth() 호출 — ETH 수량은 tx value로 전달
// selector: 0x0f4d14e9 (depositEth())
// ethcommands.ts에서는 raw calldata 방식을 사용하지만,
// 구현 시 ethers.js Contract ABI로 depositEth({ value }) 호출을 권장한다.

// L2 balance 폴링으로 확인
while (true) {
    const balance = await l2account.getBalance()
    if (balance.gte(parseEther(argv.ethamount))) return
    await sleep(100)
}
```

- `depositEth()` 함수 selector는 `0x0f4d14e9`
- ETH 수량은 calldata가 아니라 tx `value`로 전달한다
- `value`에 wei를 담아 보내면 L2 동일 주소(to == from)에 ETH가 생성됨

### 우리 구현 방향 (06-deposit-eth-to-l2.sh)

- `deployment.json`에서 inbox 주소 추출
- `L2_DEPOSITOR_PRIVATE_KEY`로 ethers.js provider 연결
- ethers.js Contract ABI로 `depositEth({ value: parseEther(L2_INITIAL_DEPOSIT_ETH) })` 호출
- ETH 수량은 calldata가 아닌 tx value로 전달 (raw calldata 조립 불필요)
- `references/nitro-testnode/scripts/ethcommands.ts`의 `bridge-funds` 로직을 참고하되, amount 전달 방식은 구현 시 재확인
- L1 tx hash 기록
- L2 RPC polling으로 depositor balance 확인
- scripts 헬퍼 컨테이너 불필요 — host에서 node 스크립트 직접 실행

---

## 7. L2 최소 Docker service 구성

### simple 모드 활용

config.ts의 `--simple` 플래그 활성화 시 sequencer 하나가 다음을 겸임한다:

```
sequencer_config.json (simple 모드):
  execution.sequencer.enable = true
  node.sequencer = true
  node.delayed-sequencer.enable = true
  node.batch-poster.enable = true           ← poster 겸임
  node.staker.enable = true                 ← staker 겸임
  node.staker.dangerous.without-block-validator = true   ← validation_node 불필요
  node.dangerous.no-sequencer-coordinator = true         ← redis 불필요
  node.batch-poster.redis-url = ""                       ← redis 불필요
```

### 최소 서비스 목록

- **`sequencer`** — 유일한 상시 Nitro 서비스. simple 모드로 실행하며 sequencer + delayed sequencer + batch-poster + staker 역할을 겸한다. L1에 batch posting과 assertion/RBlock 진행이 가능해야 한다.
- **`rollupcreator`** — 컨트랙트 배포 전용, `run --rm` (배포 시만 실행, 상시 기동 불필요)

초기 PoC 기본 구성에서 제외:

- **`validation_node`** — `without-block-validator=true`로 스킵. 이후 운영 고도화 단계에서 optional profile로 추가.
- **`redis`** — `no-sequencer-coordinator=true` + `batch-poster.redis-url=""` 설정으로 단일 sequencer에서는 불필요.

---

## 8. 후순위로 뺄 구성요소

- **`geth` + beacon + validator 서비스** — L1은 외부 프로젝트(`ethereum-pos-docker`)
- **`blockscout` + `postgres`** — 블록 탐색기, 핵심 기능 아님
- **`tokenbridge`** — L1↔L2 ERC-20 브릿지, 나중 단계
- **`das-committee-a/b`, `das-mirror`, `referenceda-provider`** — AnyTrust/DAS 미사용
- **`l3node`** — L3는 별도 프로젝트
- **`timeboost-auctioneer`, `timeboost-bid-validator`, `elasticmq`** — timeboost 미사용
- **`transaction-filterer`, `filtering-report`, `report-receiver`** — tx 필터링 미사용
- **`validation_node`** — 초기 PoC 기본 구성에서 제외. 이후 검증 고도화 단계에서 optional profile로 추가
- **`poster` 별도 서비스** — simple 모드에서 sequencer가 batch poster 역할 겸임
- **`staker-unsafe` 별도 서비스** — simple 모드에서 sequencer가 staker 역할 겸임
- **`redis`** — single sequencer simple mode에서는 제외
- **`relay`** — 고가용성 구성, 초기 PoC 불필요
- **`minio`** — 오브젝트 스토리지, AnyTrust 전용
- **`sequencer_b/c/d`** — 멀티 sequencer 구성, 초기 불필요
- **`scripts` 헬퍼 컨테이너** — host에서 node/bash 직접 실행으로 대체
- **`l1keystore` volume** — `.env` private key 방식으로 대체

---

## 9. 구현 결정사항

- **초기 PoC 구성** — "sequencer only"가 아니라 "single sequencer simple mode"다. 별도 컨테이너는 sequencer 하나지만, 내부 기능으로 batch-poster와 staker를 반드시 켠다.
- **simple 모드 채택** — sequencer 단일 서비스로 sequencer + batch-poster + staker 겸임
- **redis 제거** — `no-sequencer-coordinator=true`, `batch-poster.redis-url=""` 설정으로 불필요
- **validation_node 초기 스킵** — `node.staker.dangerous.without-block-validator=true`로 PoC 진행, 이후 추가
- **scripts 헬퍼 컨테이너 제거** — config 생성 로직을 host bash 스크립트 + inline Node.js로 재현
- **l1keystore 제거** — 모든 키는 `.env`의 `L2_*_PRIVATE_KEY` 변수로 관리
- **L1 endpoint** — `l1-chain-info.json`에서 추출, `.env` override 지원
- **deposit 방식** — ethers.js inline script로 Inbox.depositEth() 호출
- **WASM root 추출** — `docker compose run --rm --entrypoint sh sequencer` 임시 실행으로 추출 (서비스 start 전 단계)
- **l2_chain_config.json 생성** — bash + jq로 직접 생성 (TypeScript 재현 불필요)
- **sequencer_config.json 생성** — bash + jq로 직접 생성

---

## 10. 남은 리스크 / 확인 필요 사항

- **`NITRO_CONTRACTS_BRANCH` 버전 호환성** — 이미지 버전(`NITRO_NODE_IMAGE`)과 컨트랙트 브랜치가 맞아야 함. 버전 불일치 시 배포 실패 또는 sequencer 기동 실패 가능성 있음.
- **WASM module root 버전 매칭** — nitro-node 이미지와 컨트랙트가 기대하는 wasm root가 일치해야 함. `AUTHORIZE_VALIDATORS=10`으로 설정하면 validator 슬롯이 열리지만 wasm root가 다르면 assertion 실패.
- **PoS L1 finality 요구** — nitro의 batch-poster는 L1 finality를 기다릴 수 있음. `wait-for-l1-finality=false`로 설정하면 devnet에서 빠르게 동작하지만, L1이 느리면 batch posting 지연 가능.
- **L1 RPC WebSocket 안정성** — sequencer의 `parent-chain.connection.url`은 WS를 요구함. L1이 다른 인스턴스에 있으면 WS 연결 유지가 중요.
- **deployment.json inbox 필드 타입** — `ethcommands.ts`에서 `ethers.utils.hexlify(deploydata.inbox)` 사용. `deploydata.inbox`가 이미 hex string인지 bytes인지 확인 필요.
- **L2 genesis alloc 금지 준수** — `l2_chain_config.json`에 `alloc` 필드를 절대 넣지 않음. ETH는 L1→L2 deposit으로만 공급.
- **sequencer feed port** — 기본 9642. L3 구축 시 이 port를 parent feed로 사용하므로 열려 있어야 함.

---

이 분석을 기준으로 `projects/arbitrum-l2-docker` 구현을 진행한다.
