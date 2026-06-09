# arbitrum-l2-docker — 최초 실행 Runbook

L1 / L2 / L3 devnet 최초 실행 순서, 파일 복사 흐름, 각 명령의 입출력 파일과 체인 동작을 정리한 운영 가이드입니다.

---

## 전체 구조 개요

```
projects/
  ethereum-pos-docker/          ← L1 devnet (Geth + Prysm)
  arbitrum-l2-docker/           ← L2 devnet (Arbitrum Nitro)
  arbitrum-l3-docker/           ← L3 devnet (향후 — 같은 패턴)
```

**핵심 원칙**:

- L2는 자체 L1 geth를 띄우지 않습니다. 외부 `ethereum-pos-docker`를 parent chain으로 사용합니다.
- L3는 자체 L2 geth를 띄우지 않습니다. 외부 `arbitrum-l2-docker`를 parent chain으로 사용합니다.
- L2/L3 genesis에 ETH를 직접 넣지 않습니다 (genesis prefund 금지). ETH는 반드시 `L1→L2 deposit` → `L2 배분` 순서로 공급합니다.
- `sequencer_config.json`은 런타임 private key를 포함합니다. **절대 커밋하지 마십시오**.
- 모든 artifact에 private key/mnemonic/secret이 포함되지 않도록 생성 직후 자동 검증합니다.

---

## 파일 복사 흐름

각 레이어 프로젝트는 이전 레이어의 artifact를 자신의 `config/` 디렉터리로 복사하여 parent chain으로 인식합니다.

```
[L1 생성]
  ethereum-pos-docker/artifacts/l1-chain-info.json
          │
          │  cp
          ▼
  arbitrum-l2-docker/config/l1-chain-info.json     ← L2가 읽는 L1 parent config

[L2 생성]
  arbitrum-l2-docker/artifacts/l2-chain-info.json
          │
          │  cp
          ▼
  arbitrum-l3-docker/config/l2-chain-info.json     ← L3가 읽는 L2 parent config (향후)
```

---

## ETH 공급 흐름

genesis prefund 없이 순차 자금 조달 방식을 사용합니다.

```
[L1 genesis]
  L2_DEPOSITOR_ADDRESS  ← 1,000,000,000 ETH  (ethereum-pos-docker가 genesis에서 prefund)

[L2 fund:l1] — L1 pre-distribution (depositor → L2 role 계정, L1 tx 수수료용)
  deployer     ← 1,000 ETH   (L1에서 rollup contracts 배포)
  batch_poster ← 1,000 ETH   (L1 sequencerInbox에 batch 전송)
  validator    ← 1,000 ETH   (L1 rollup에 assertion 게시)

[L2 deploy]   — deployer가 L1에 L2 rollup/system contracts 배포

[L2 start]    — L2 sequencer 기동

[L2 deposit]  — L1 → L2 ETH deposit  (Inbox.depositEth)
  depositor L1 → depositor L2  = 500,000,000 ETH

[L2 distribute] — L2 role 계정 배분  (depositor L2 → 각 role)
  deployer     ← 1,000 ETH
  rollup_owner ← 1,000 ETH
  sequencer    ← 1,000 ETH
  batch_poster ← 1,000 ETH
  validator    ← 1,000 ETH
  test_user    ←   100 ETH  (optional)

─────────────────────────────────────── (향후 L3도 동일 패턴)
[L3 fund:l2] — L2 pre-distribution
  l3_deployer     ← 1,000 ETH (L2 상에서)
  l3_batch_poster ← 1,000 ETH
  l3_validator    ← 1,000 ETH

[L3 deposit]  — L2 → L3 ETH deposit
  l3_depositor L2 → l3_depositor L3  = 300,000,000 ETH (예시)

[L3 distribute] — L3 role 계정 배분
  각 role  ← 1,000 ETH
```

**parent-chain gas vs child-chain gas**:

| 구분 | 설명 |
|------|------|
| **parent-chain gas** | batch_poster가 L1 sequencerInbox에 batch를 올릴 때 소모 (L1 ETH). validator가 L1 rollup에 assertion을 게시할 때 소모 (L1 ETH). `fund:l1` 단계에서 사전 조달. |
| **child-chain gas** | L2 사용자 트랜잭션 실행 시 소모 (L2 ETH). `deposit` + `distribute` 단계에서 공급. |

---

## STEP 0 — L1 실행 (ethereum-pos-docker)

### 위치

```
projects/ethereum-pos-docker/
```

### 명령 순서

```bash
cd projects/ethereum-pos-docker

pnpm install
cp .env.sample .env
# .env 편집:
#   L2_DEPOSITOR_ADDRESS=0x...          (L2 부트스트랩 계정 주소 — public only)
#   L2_DEPOSITOR_PREFUND_BALANCE_ETH=1000000000

pnpm run check
pnpm run generate    # genesis.json, genesis.ssz, config.yml 생성 (최초 1회)
pnpm run init        # geth DB 초기화 (최초 1회)
pnpm run start       # 전체 노드 기동
pnpm run peer:connect
pnpm run verify
pnpm run export:artifact
```

### export:artifact 생성 파일

`artifacts/l1-chain-info.json`:

```json
{
  "chainId": 1111,
  "networkId": 1111,
  "executionRpc": {
    "node0": "http://localhost:8545",
    "node1": "http://localhost:8645"
  },
  "executionWs": {
    "node0": "ws://localhost:8546",
    "node1": "ws://localhost:8646"
  },
  "beaconRest": {
    "node0": "http://localhost:3500",
    "node1": "http://localhost:3600"
  },
  "finalizedEpoch": 3,
  "peerCount": 2,
  "prefundedAccounts": {
    "l2Depositor": {
      "address": "0x...",
      "balance": "1000000000000000000000000000"
    }
  },
  "generatedAt": "2026-06-09T10:00:00Z"
}
```

포함 금지: private key, mnemonic, keystore password.

---

## STEP 1 — L1 artifact를 L2 config로 복사

```bash
cp projects/ethereum-pos-docker/artifacts/l1-chain-info.json \
   projects/arbitrum-l2-docker/config/l1-chain-info.json
```

이 복사 이후 L2 프로젝트는 `config/l1-chain-info.json`에 적힌 외부 L1 RPC/WS를 parent chain으로 사용합니다.

---

## STEP 2 — L2 실행 (arbitrum-l2-docker)

### 위치

```
projects/arbitrum-l2-docker/
```

### 사전 준비

```bash
cd projects/arbitrum-l2-docker
pnpm install
cp .env.sample .env
```

`.env` 필수 설정 (모든 항목 required — L2_VALIDATOR_ADDRESS/KEY 포함):

```
L2_CHAIN_ID=1721702
L2_CHAIN_NAME=l2-devnet

L2_DEPOSITOR_ADDRESS=0x...          # l1-chain-info.json의 l2Depositor와 동일해야 함
L2_DEPOSITOR_PRIVATE_KEY=0x...

L2_DEPLOYER_ADDRESS=0x...
L2_DEPLOYER_PRIVATE_KEY=0x...

L2_ROLLUP_OWNER_ADDRESS=0x...
L2_ROLLUP_OWNER_PRIVATE_KEY=0x...

L2_SEQUENCER_ADDRESS=0x...
L2_SEQUENCER_PRIVATE_KEY=0x...

L2_BATCH_POSTER_ADDRESS=0x...
L2_BATCH_POSTER_PRIVATE_KEY=0x...

L2_VALIDATOR_ADDRESS=0x...          # required (staker 필수)
L2_VALIDATOR_PRIVATE_KEY=0x...      # required

# L1 role 자금 조달 금액
L1_DEPLOYER_FUND_ETH=1000
L1_BATCH_POSTER_FUND_ETH=1000
L1_VALIDATOR_FUND_ETH=1000

# L1 → L2 deposit 금액
L1_TO_L2_DEPOSIT_ETH=500000000

# L2 role 배분 금액
L2_DEPLOYER_FUND_ETH=1000
L2_ROLLUP_OWNER_FUND_ETH=1000
L2_SEQUENCER_FUND_ETH=1000
L2_BATCH_POSTER_FUND_ETH=1000
L2_VALIDATOR_FUND_ETH=1000
L2_TEST_USER_FUND_ETH=100
```

### 전체 파이프라인 (자동)

```bash
pnpm run up
```

> `up` = check → load:l1 → fund:l1 → config:chain → deploy → config:node → start → deposit → distribute → verify → export:artifact

### 단계별 실행

```bash
pnpm run check
pnpm run load:l1
pnpm run fund:l1
pnpm run config:chain
pnpm run deploy
pnpm run config:node
pnpm run start
pnpm run deposit
pnpm run distribute
pnpm run verify
pnpm run export:artifact
```

---

## 각 명령 상세

### `pnpm run check`

읽는 파일:
- `.env`
- `package.json`
- `docker-compose.yaml`
- `config/l1-chain-info.json`

확인 내용:
- 필수 command 존재 (`docker`, `jq`, `curl`, `node`, `pnpm`)
- node_modules 설치 여부
- 필수 env 값 존재 (private key, address 포함 전 항목)
- private key / address 형식 검증 (`0x` prefix, 길이)
- `config/l1-chain-info.json` 존재 여부

생성 파일: 없음

실패 조건:
- `config/l1-chain-info.json` 없음
- 필수 private key 누락 (deployer / batch_poster / validator / depositor)
- 필수 address 누락
- 필수 command 미설치
- node_modules 없음

---

### `pnpm run load:l1`

읽는 파일:
- `config/l1-chain-info.json`
- `.env` (L2_DEPOSITOR_ADDRESS 비교용)

수행 동작:
- L1 RPC에 실제 연결 (`eth_chainId`)
- artifact의 chainId와 L1 응답 chainId 일치 확인
- `.env`의 `L2_DEPOSITOR_ADDRESS`가 artifact의 `prefundedAccounts.l2Depositor.address`와 일치하는지 확인
- L1 RPC / WS endpoint를 내부 변수로 export (이후 단계에서 `PARENT_CHAIN_RPC`, `PARENT_CHAIN_WS`로 사용)

생성 파일:
- `config/resolved-l1-config.env` (이후 단계가 source하는 shell 환경 파일)

실패 조건:
- L1 RPC 연결 실패 (`ethereum-pos-docker` 미기동)
- chainId 불일치
- depositor 주소 불일치
- L1 finalized 상태 비정상

---

### `pnpm run fund:l1`

스크립트: `scripts/02-fund-l1-role-accounts.sh` + `scripts/js/fund-l1-accounts.js`

읽는 파일:
- `.env`
- `config/l1-chain-info.json` (L1 RPC endpoint)

읽는 env:
- `L2_DEPOSITOR_PRIVATE_KEY`, `L2_DEPOSITOR_ADDRESS`
- `L2_DEPLOYER_ADDRESS`, `L2_BATCH_POSTER_ADDRESS`, `L2_VALIDATOR_ADDRESS`
- `L1_DEPLOYER_FUND_ETH`, `L1_BATCH_POSTER_FUND_ETH`, `L1_VALIDATOR_FUND_ETH`

수행 동작:
1. `L2_DEPOSITOR_PRIVATE_KEY` → 주소 파생 → `L2_DEPOSITOR_ADDRESS`와 일치 확인
2. depositor의 L1 잔액 확인 (총 전송 필요 금액 이상이어야 함)
3. 각 role 계정의 현재 L1 잔액 확인 → 이미 충분하면 skip
4. deployer에게 1,000 ETH 전송 (L1 tx)
5. batch_poster에게 1,000 ETH 전송 (L1 tx)
6. validator에게 1,000 ETH 전송 (L1 tx)
7. `--force` 옵션 시 잔액 무관 재전송

생성 파일:
- `artifacts/fund-l1-accounts.json`

```json
{
  "timestamp": "2026-06-09T10:10:00Z",
  "depositor": "0x...",
  "distributions": [
    {
      "role": "deployer",
      "address": "0x...",
      "amountEth": "1000",
      "txHash": "0x...",
      "balanceBeforeEth": "0",
      "balanceAfterEth": "1000",
      "status": "funded"
    }
  ]
}
```

포함 금지: private key

실패 조건:
- depositor private key / address 불일치
- depositor L1 잔액 부족
- target address 형식 오류
- L1 RPC 연결 실패
- tx 실패

---

### `pnpm run config:chain`

스크립트: `scripts/02-render-chain-config.sh`

읽는 파일:
- `.env`
- `config/l1-chain-info.json`

읽는 env:
- `L2_CHAIN_ID`, `L2_CHAIN_NAME`
- `L2_ROLLUP_OWNER_ADDRESS`, `L2_SEQUENCER_ADDRESS`
- `L2_BATCH_POSTER_ADDRESS`, `L2_VALIDATOR_ADDRESS`

수행 동작:
- Arbitrum rollupcreator 입력용 `l2_chain_config.json` 생성
- L2 genesis에 prefund 블록 없음 (genesis prefund 금지)
- parent chainId는 `l1-chain-info.json`에서 읽음

생성 파일:
- `config/l2_chain_config.json`

실패 조건:
- parent chainId 누락
- L2 chainId 누락
- 필수 role address 누락

---

### `pnpm run deploy`

스크립트: `scripts/03-deploy-rollup.sh`

읽는 파일:
- `.env`
- `config/l1-chain-info.json`
- `config/l2_chain_config.json`
- `artifacts/fund-l1-accounts.json` (deployer L1 잔액 검증용)

읽는 env:
- `L2_DEPLOYER_PRIVATE_KEY`, `L2_DEPLOYER_ADDRESS`

수행 동작:
1. `L2_DEPLOYER_PRIVATE_KEY` → 주소 파생 → `L2_DEPLOYER_ADDRESS` 일치 확인
2. deployer의 L1 ETH 잔액 확인 (0이면 `fund:l1` 재실행 안내 후 FAIL)
3. `rollupcreator` Docker 컨테이너 일회성 실행
4. L1에 Arbitrum rollup/system contracts 배포:
   - `RollupCreator` 호출
   - rollup, bridge, inbox, outbox, sequencerInbox, rollupEventInbox 배포
5. 배포 결과 파싱 → artifact 저장
6. `l2_chain_info.json` 형식으로 변환 저장 (sequencer node가 읽는 형식)

생성 파일:
- `artifacts/deployment.json` — 배포된 컨트랙트 주소
- `artifacts/deployed_chain_info.json` — rollupcreator 원본 출력
- `config/l2_chain_info.json` — sequencer node 입력 형식

포함 금지: private key

실패 조건:
- deployer private key / address 불일치
- deployer L1 ETH 잔액 0 (`pnpm run fund:l1` 필요)
- rollupcreator 컨테이너 빌드/실행 실패
- L1 RPC 연결 실패
- 배포 결과 파일 누락

---

### `pnpm run config:node`

스크립트: `scripts/04-render-node-configs.sh`

읽는 파일:
- `.env`
- `config/l1-chain-info.json`
- `config/l2_chain_info.json`
- `artifacts/deployment.json`

읽는 env:
- `L2_BATCH_POSTER_PRIVATE_KEY`, `L2_BATCH_POSTER_ADDRESS`
- `L2_VALIDATOR_PRIVATE_KEY`, `L2_VALIDATOR_ADDRESS`
- `L2_CHAIN_ID`

수행 동작:
1. `L2_BATCH_POSTER_PRIVATE_KEY` → 주소 파생 → `L2_BATCH_POSTER_ADDRESS` 일치 확인
2. batch_poster의 L1 ETH 잔액 확인 (0이면 FAIL)
3. `L2_VALIDATOR_PRIVATE_KEY` → 주소 파생 → `L2_VALIDATOR_ADDRESS` 일치 확인
4. validator의 L1 ETH 잔액 확인 (0이면 FAIL)
5. `sequencer_config.json` 생성:
   - `execution.sequencer.enable = true`
   - `node.sequencer = true`
   - `node.delayed-sequencer.enable = true`
   - `node.batch-poster.enable = true`
   - `node.staker.enable = true` (고정 — fallback 불가)
   - `node.staker.dangerous.without-block-validator = true`
   - `node.dangerous.no-sequencer-coordinator = true`
   - `node.batch-poster.redis-url = ""`
   - `parent-chain.connection.url` = `PARENT_CHAIN_WS` (localhost → `host.docker.internal` 자동 변환)

생성 파일:
- `config/sequencer_config.json`

> **주의**: `sequencer_config.json`은 `L2_BATCH_POSTER_PRIVATE_KEY`와 `L2_VALIDATOR_PRIVATE_KEY`를 포함합니다. `.gitignore`에 등록되어 있으며 절대 커밋하지 마십시오.

실패 조건:
- `config/l2_chain_info.json` 없음
- batch_poster key / address 불일치
- validator key / address 불일치
- batch_poster L1 ETH 잔액 0
- validator L1 ETH 잔액 0
- staker 비활성화 설정 시 FAIL (정책 위반)
- batch-poster 비활성화 설정 시 FAIL

---

### `pnpm run start`

스크립트: `scripts/05-start-l2.sh`

읽는 파일:
- `docker-compose.yaml`
- `config/sequencer_config.json`
- `config/l2_chain_info.json`
- `artifacts/deployment.json`

수행 동작:
1. `sequencer_config.json` 정책 검증 (batch-poster.enable, staker.enable = true)
2. 현재 L1 block number 기록 (l2-start.json용)
3. `docker compose up -d sequencer` 실행
4. L2 RPC 응답 대기 (최대 120초)
5. L2 chainId 검증
6. L2 block number 증가 확인 (최대 60초 — 미증가 시 FAIL)
7. start 시점 정보 저장

생성 파일:
- `artifacts/l2-start.json`

```json
{
  "l1BlockAtStart": 42,
  "l2BlockAtStart": 0,
  "startedAt": "2026-06-09T10:20:00Z",
  "l2ChainId": 1721702,
  "parentChainId": 1111
}
```

실패 조건:
- `sequencer_config.json` 없음
- `l2_chain_info.json` 없음
- `deployment.json` 없음
- staker / batch-poster 비활성화 감지
- L2 RPC 120초 내 미응답
- L2 chainId 불일치
- 60초 내 L2 block number 미증가

---

### `pnpm run deposit`

스크립트: `scripts/06-deposit-eth-to-l2.sh` + `scripts/js/deposit.js`

읽는 파일:
- `.env`
- `config/l1-chain-info.json`
- `artifacts/deployment.json` (inbox address)

읽는 env:
- `L2_DEPOSITOR_PRIVATE_KEY`, `L2_DEPOSITOR_ADDRESS`
- `L1_TO_L2_DEPOSIT_ETH` (기본 500,000,000)

수행 동작:
1. `L2_DEPOSITOR_PRIVATE_KEY` → 주소 파생 → `L2_DEPOSITOR_ADDRESS` 일치 확인
2. L1 depositor 잔액 확인
3. L2 depositor의 deposit 전 잔액 기록 (`l2BalanceBefore`)
4. L1 `Inbox.depositEth(maxSubmissionCost)` 호출 (ETH amount = tx value로 전달)
   - `maxSubmissionCost = 143,000,000,000,000 wei`
5. L1 tx receipt 확인
6. L2 depositor balance 폴링 → `l2BalanceBefore + depositAmount` 이상이 될 때까지 대기

생성 파일:
- `artifacts/deposit-l1-to-l2.json`

```json
{
  "from": "0x...",
  "inboxAddress": "0x...",
  "amountEth": "500000000",
  "l1TxHash": "0x...",
  "l1BlockNumber": 55,
  "l2BalanceBeforeEth": "0",
  "l2BalanceAfterEth": "500000000",
  "status": "confirmed",
  "timestamp": "2026-06-09T10:25:00Z"
}
```

포함 금지: private key

실패 조건:
- depositor private key / address 불일치
- L1 depositor 잔액 부족
- Inbox address 없음 또는 형식 오류
- deposit tx 실패
- L2 balance polling timeout

---

### `pnpm run distribute`

스크립트: `scripts/07-distribute-l2-eth.sh` + `scripts/js/distribute.js`

읽는 파일:
- `.env`
- `artifacts/deposit-l1-to-l2.json` (사전 조건 확인)

읽는 env:
- `L2_DEPOSITOR_PRIVATE_KEY`, `L2_DEPOSITOR_ADDRESS`
- `L2_DEPLOYER_ADDRESS`, `L2_ROLLUP_OWNER_ADDRESS`, `L2_SEQUENCER_ADDRESS`
- `L2_BATCH_POSTER_ADDRESS`, `L2_VALIDATOR_ADDRESS`, `L2_TEST_USER_ADDRESS`
- `L2_DEPLOYER_FUND_ETH`, `L2_ROLLUP_OWNER_FUND_ETH`, `L2_SEQUENCER_FUND_ETH`
- `L2_BATCH_POSTER_FUND_ETH`, `L2_VALIDATOR_FUND_ETH`, `L2_TEST_USER_FUND_ETH`

수행 동작:
1. `L2_DEPOSITOR_PRIVATE_KEY` → 주소 파생 → `L2_DEPOSITOR_ADDRESS` 일치 확인
2. L2 depositor 잔액 확인 (총 필요 금액 이상이어야 함)
3. 각 role 계정 현재 잔액 확인 → 이미 충분하면 skip
4. required roles (deployer, rollupOwner, sequencer, batchPoster, validator): 주소 없으면 FAIL
5. optional role (testUser): 주소 없으면 skip
6. 각 계정에 L2 ETH 전송
7. `--force` 옵션 시 잔액 무관 재전송

생성 파일:
- `artifacts/fund-l2-accounts.json`

포함 금지: private key

실패 조건:
- depositor private key / address 불일치
- `deposit-l1-to-l2.json` 없음 (deposit 미실행)
- L2 depositor 잔액 부족
- required role address 없음 또는 형식 오류
- tx 실패

---

### `pnpm run verify`

스크립트: `scripts/08-verify.sh`

읽는 파일:
- `config/l1-chain-info.json`
- `config/sequencer_config.json`
- `artifacts/deployment.json`
- `artifacts/l2-start.json` (fromBlock 기준)

확인 항목 및 판정:

| 항목 | FAIL 조건 | WARN 조건 |
|------|-----------|-----------|
| L1 RPC 연결 | 응답 없음 | — |
| L1 chainId | 불일치 | — |
| L2 RPC 연결 | 응답 없음 | — |
| L2 chainId | 불일치 | — |
| L2 block 증가 | 6초 내 미증가 | — |
| rollup contract code | 없음 | — |
| bridge/inbox/outbox/seqInbox code | 없음 | — |
| batch-poster.enable | false | — |
| staker.enable | false | — |
| sequencer 컨테이너 | 중지 상태 | — |
| sequencerInbox 이벤트 (fromBlock=l1BlockAtStart) | — | 이벤트 없음 |
| rollup 이벤트 (fromBlock=l1BlockAtStart) | — | 이벤트 없음 |
| L2 account balance | — | 0 wei |
| sequencer feed port | — | 미응답 |

`fromBlock=0x0` 기준의 과거 이벤트만으로 batch/assertion OK 처리하지 않습니다.

생성 파일: 없음 (향후 `artifacts/verify-summary.json` 추가 예정)

실패 조건:
- 위 FAIL 항목 해당

---

### `pnpm run export:artifact`

스크립트: `scripts/09-export-artifact.sh`

읽는 파일 (모두 필수):
- `config/l2_chain_info.json`
- `artifacts/deployment.json`
- `artifacts/fund-l1-accounts.json`
- `artifacts/l2-start.json`
- `artifacts/deposit-l1-to-l2.json`
- `artifacts/fund-l2-accounts.json`

수행 동작:
1. 필수 파일 전체 존재 확인
2. L2 컨트랙트 주소 추출 (`l2_chain_info.json` 우선, `deployment.json` fallback)
3. `l2-chain-info.json` 생성
4. 생성 후 private key 포함 여부 자동 검증 (감지 시 파일 삭제 후 FAIL)

생성 파일:
- `artifacts/l2-chain-info.json`

`l2-chain-info.json` 포함 항목:
- `chainId`, `networkId`, `chainName`, `parentChainId`
- `executionRpc.sequencer`, `executionWs.sequencer`
- `sequencerFeed.url`
- `rollup.*` (rollup, bridge, inbox, outbox, sequencerInbox, rollupEventInbox)
- `accounts.*` (l2Depositor, deployer, rollupOwner, sequencer, batchPoster, validator — **public address only**)
- `l1Funding` (fund-l1-accounts 요약)
- `l2Start` (l2-start 정보)
- `deposit` (deposit 결과)
- `fundedAccounts` (fund-l2 요약)
- `generatedAt`

포함 금지: private key, mnemonic, secret

실패 조건:
- 필수 artifact 파일 누락
- private key 포함 감지

---

### `pnpm run stop`

```bash
docker compose stop sequencer
```

artifacts / config / `.env` 삭제하지 않음. sequencer data volume 유지.

---

### `pnpm run clean`

생성된 config 및 artifacts 정리, `docker compose down`.

- `.env` 삭제 안 함
- `config/l1-chain-info.json` 기본 삭제 안 함
- `--volumes` 옵션 시 sequencer data volume 삭제 (destructive — 로그에 명확히 표시)

---

## 명령 요약 표

| 명령 | 읽는 주요 파일 | 생성 파일 | 수행 chain 동작 | 주요 실패 원인 |
|------|----------------|-----------|-----------------|----------------|
| `check` | `.env`, `l1-chain-info.json` | — | — | l1-chain-info 없음, 필수 key 누락, command 미설치 |
| `load:l1` | `l1-chain-info.json`, `.env` | `resolved-l1-config.env` | L1 RPC chainId 조회, depositor 확인 | L1 미기동, chainId/depositor 불일치 |
| `fund:l1` | `.env`, `l1-chain-info.json` | `fund-l1-accounts.json` | L1: depositor → deployer/batchPoster/validator ETH 전송 | depositor 잔액 부족, key/address 불일치 |
| `config:chain` | `.env`, `l1-chain-info.json` | `l2_chain_config.json` | — | chainId 누락, role address 누락 |
| `deploy` | `.env`, `l2_chain_config.json`, `l1-chain-info.json` | `deployment.json`, `l2_chain_info.json` | L1: rollup/system contracts 배포 | deployer L1 ETH 부족, rollupcreator 실패 |
| `config:node` | `.env`, `l2_chain_info.json`, `deployment.json` | `sequencer_config.json` | L1 batchPoster/validator 잔액 조회 | key/address 불일치, L1 잔액 0 |
| `start` | `sequencer_config.json`, `l2_chain_info.json` | `l2-start.json` | L2 sequencer 기동, block 생성 확인 | RPC 무응답, chainId 불일치, block 미증가 |
| `deposit` | `.env`, `deployment.json` | `deposit-l1-to-l2.json` | L1→L2: Inbox.depositEth 호출 | depositor L1 ETH 부족, L2 balance polling timeout |
| `distribute` | `.env`, `deposit-l1-to-l2.json` | `fund-l2-accounts.json` | L2: depositor → role 계정 ETH 전송 | depositor L2 ETH 부족, required address 누락 |
| `verify` | 위 artifact 전체, `l2-start.json` | — | L1/L2 contract/event/block 검증 | batch-poster/staker 비활성화, block 미증가 |
| `export:artifact` | 위 artifact 전체 | `l2-chain-info.json` | — | 필수 artifact 누락, private key 포함 감지 |

---

## STEP 3 — L2 artifact를 L3 config로 복사 (향후)

```bash
cp projects/arbitrum-l2-docker/artifacts/l2-chain-info.json \
   projects/arbitrum-l3-docker/config/l2-chain-info.json
```

---

## STEP 4 — L3 실행 흐름 (향후)

L2와 동일한 패턴을 따릅니다. 차이점:

| 항목 | L2 | L3 |
|------|----|----|
| parent chain | L1 (ethereum-pos-docker) | L2 (arbitrum-l2-docker) |
| parent config | `config/l1-chain-info.json` | `config/l2-chain-info.json` |
| deployer gas source | L1 ETH (fund:l1) | L2 ETH (fund:l2) |
| deposit source | L1 → L2 (L1 Inbox) | L2 → L3 (L2 Inbox) |
| artifact | `l2-chain-info.json` | `l3-chain-info.json` |

**L3 genesis prefund 금지** — L2와 동일하게 deposit 플로우로만 ETH 공급.

---

## 보안 체크리스트

- [ ] `config/sequencer_config.json` — `.gitignore` 확인 (private key 포함)
- [ ] `artifacts/*.json` — private key 포함 안 됨 (생성 시 자동 검증)
- [ ] `.env` — `.gitignore` 확인
- [ ] L2/L3 genesis에 `alloc` 블록 없음 확인
- [ ] `docker-compose.yaml`에 L1 geth 서비스 없음 확인
- [ ] `sequencer_config.json`의 `node.staker.enable = true` 확인
- [ ] `sequencer_config.yaml`의 `node.batch-poster.enable = true` 확인
