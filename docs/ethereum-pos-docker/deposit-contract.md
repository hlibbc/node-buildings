# Deposit Contract와 Devnet Stub

Ethereum PoS Deposit Contract의 역할과, 이번 devnet에서 stub이 필요했던 이유를 설명합니다.

---

## 1. Deposit Contract란

Ethereum PoS에서 새로운 validator가 되기 위해 ETH 32개를 예치하는 진입점입니다.  
Execution Layer(Geth)에 배포된 특수 컨트랙트로, 예치 시 `DepositEvent`를 발생시킵니다.  
Consensus Layer(Prysm)는 이 이벤트 로그를 주기적으로 읽어 validator registry에 반영합니다.

```
Execution Layer (Geth)
  └─ Deposit Contract  ← 0x4242424242424242424242424242424242424242
       └─ DepositEvent 발생

Consensus Layer (Prysm Beacon)
  └─ processPastLogs()  ← Geth에 eth_getLogs 요청
       └─ validator 활성화 처리
```

이 흐름 덕분에 Ethereum mainnet에서는 validator가 on-chain deposit을 통해 permissionless하게 합류할 수 있습니다.

---

## 2. 일반 Staking Contract와의 차이

Deposit Contract는 DeFi staking pool과 다릅니다.

- **DeFi staking pool**: 사용자 ETH를 모아 운용, 자체 토큰 발행, 프로토콜과 무관
- **Deposit Contract**: consensus layer와 통신하는 protocol-level bridge

Deposit Contract를 통해 예치한 ETH는 beacon chain validator 활성화로 이어지며, withdrawal credential을 통해서만 출금됩니다. Execution Layer 스마트 컨트랙트 로직이 아니라 consensus 레이어가 그 상태를 관리합니다.

---

## 3. Devnet에서도 Deposit Contract 주소가 필요한 이유

이번 devnet은 `--interop-start-index`, `--interop-num-validators` 옵션으로 validator를 생성합니다.  
실제 on-chain deposit 없이 genesis 상태에 validator를 미리 주입하는 방식입니다.

그럼에도 **Prysm은 startup 시점과 주기적으로 Deposit Contract 주소의 코드를 확인합니다.**

```
Prysm 내부 흐름 (processPastLogs)
  1. config.yml의 DEPOSIT_CONTRACT_ADDRESS 읽기
  2. eth_getCode(DEPOSIT_CONTRACT_ADDRESS) 호출
  3. 코드 없음 → "no contract code at given address" 에러
  4. ETH1 service를 offline으로 전환
  5. el_offline=true
```

이 확인은 "deposit이 있냐"가 아니라 "Execution Layer가 정상 상태냐"를 판단하는 체크입니다.  
코드가 없으면 Prysm은 EL 연결 자체를 비정상으로 간주합니다.

---

## 4. 이번 버그: 증상과 원인

**관측된 증상**

- `curl /eth/v1/node/syncing` → `el_offline: true`
- beacon log: `processPastLogs: abi: attempting to unmarshal an empty string`
- validator log: `Could not get local payload / payload status is SYNCING or ACCEPTED`
- `head_slot=0` 정체, `finalized_epoch=0` 지속

**원인 연쇄**

```
DEPOSIT_CONTRACT_ADDRESS=0x0000000000000000000000000000000000000000
          ↓
eth_getCode(0x0000...) = empty  (genesis alloc에 코드 없음)
          ↓
Prysm: "no contract code at given address"
          ↓
el_offline=true
          ↓
engine_forkchoiceUpdated → payload 생성 불가
          ↓
head_slot 정체, finality 없음
```

---

## 5. 수정 내용

**수정 파일**: `scripts/00-generate-config.sh`

두 가지를 함께 수정해야 합니다.

**① DEPOSIT_CONTRACT_ADDRESS 변경**

```yaml
# config.yml
DEPOSIT_CONTRACT_ADDRESS: 0x4242424242424242424242424242424242424242
```

`0x0000...` 주소는 Ethereum 프로토콜에서 burn address로 취급되며 코드를 가질 수 없습니다.  
실제로 사용할 주소로 변경합니다.

**② genesis.json alloc에 stub bytecode 주입**

```json
"alloc": {
  "4242424242424242424242424242424242424242": {
    "code": "0x600436106100255760003560e01c8063c5f2892f1461002b578063621fd1301461003257505b60206000f35b5060206000f35b506020600052600860205260606000f3",
    "balance": "0x0"
  }
}
```

stub은 두 함수에 응답합니다.

- `get_deposit_root()` (selector `0xc5f2892f`) → 32 zero bytes (`bytes32`)
- `get_deposit_count()` (selector `0x621fd130`) → 8 zero bytes ABI-encoded (`bytes memory`)
- 나머지 → 32 zero bytes fallback

단순 `STOP` opcode(`0x00`)를 넣으면 Prysm의 ABI decode가 실패합니다.  
빈 반환값을 `bytes32`/`bytes memory`로 unmarshal하려다 에러가 납니다.

---

## 6. 주입 타이밍이 중요한 이유

**genesis.ssz와 genesis.json은 반드시 같은 genesis 상태를 기반으로 생성되어야 합니다.**

```
prysmctl generate-genesis
  └─ genesis.json 읽어서 execution genesis block hash 계산
  └─ genesis.ssz의 latest_execution_payload_header.block_hash 에 기록

geth init genesis.json
  └─ 같은 genesis.json으로 block 0 생성
  └─ genesis block hash 계산
```

`genesis.json alloc`에 deposit contract stub이 있을 때와 없을 때 genesis block hash가 달라집니다.

- stub을 **prysmctl 이전**에 주입하면: 두 genesis hash 일치 → 정상
- stub을 **prysmctl 이후**에만 genesis.json에 추가하면: beacon은 stub 없는 hash, geth는 stub 있는 hash → 불일치

불일치 시 증상:

```
beacon log: payload status is SYNCING or ACCEPTED
beacon log: headPayloadBlockHash=0x000000000000
head_slot=0 정체
```

`scripts/00-generate-config.sh`에서는 `jq` 템플릿 내부에서 deposit contract를 alloc에 포함시킨 뒤 `prysmctl`을 실행합니다.

---

## 7. genesis.json과 genesis.ssz의 관계

```
genesis.json
  - Execution Layer config
  - alloc (deposit contract stub 포함)
  - chainId, forks, gasLimit 등
  → geth init 에 사용

genesis.ssz
  - Consensus Layer config
  - validator 목록 (interop 생성)
  - latest_execution_payload_header.block_hash
    ← genesis.json으로부터 파생
  → beacon node --genesis-state 에 사용
```

양쪽이 같은 `genesis.json`을 보고 만들어져야 `block_hash`가 일치합니다.

---

## 8. 검증 방법

체인이 기동된 후 아래 명령으로 상태를 확인합니다.

```bash
# 전체 검증
pnpm run verify

# 상태 확인
pnpm run status

# node0/node1 syncing 상태
curl -s http://localhost:3500/eth/v1/node/syncing | jq
curl -s http://localhost:3600/eth/v1/node/syncing | jq

# finality 확인
curl -s http://localhost:3500/eth/v1/beacon/states/head/finality_checkpoints | jq
curl -s http://localhost:3600/eth/v1/beacon/states/head/finality_checkpoints | jq
```

**성공 기준**

- `el_offline: false`
- `head_slot` 증가
- `finalized.epoch > 0`
- validator[0], validator[32] `active_ongoing`
- `pnpm run verify` FAIL=0
