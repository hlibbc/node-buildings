# L1 Chain-Info Artifact

L2/L3 Docker 프로젝트가 이 L1 devnet을 parent chain으로 참조할 때 사용하는 artifact 파일 설명입니다.

---

## 1. artifact가 필요한 이유

L2/L3 체인을 기동할 때 parent chain(L1)의 아래 정보가 필요합니다.

- RPC 엔드포인트 (chainId, RPC URL)
- Deposit Contract 주소
- 현재 블록 번호, finality 상태
- prefund된 계정 목록

이 정보를 스크립트에 직접 하드코딩하면 L1 설정이 바뀔 때마다 수동 동기화가 필요합니다.  
`l1-chain-info.json`은 L1이 기동된 시점의 상태를 기록해두고, L2/L3가 이를 참조하는 구조입니다.

```
ethereum-pos-docker/
  └─ artifacts/l1-chain-info.json   ← L1 기동 후 생성
        ↓ 참조
ethereum-nitro-docker/
  └─ config/l1-chain-info.json      ← 복사 또는 심볼릭 링크
```

---

## 2. 생성 방법

L1 devnet이 아래 조건을 충족한 후 실행합니다.

- `el_offline=false` (두 노드 모두)
- `beacon peers >= 1` (두 노드 모두)
- `finalized epoch > 0` (두 노드 모두)

```bash
# 상태 확인
pnpm run verify

# artifact 생성
pnpm run export:artifact
```

생성 파일: `artifacts/l1-chain-info.json`

---

## 3. 필드 설명

```
{
  chainId            — EVM 체인 ID (CHAIN_ID, 기본 1111)
  networkId          — EVM 네트워크 ID (NETWORK_ID, 기본 1111)

  executionRpc       — Geth HTTP JSON-RPC 엔드포인트
    node0              http://localhost:8545
    node1              http://localhost:8645

  executionWs        — Geth WebSocket JSON-RPC 엔드포인트
    node0              ws://localhost:8546
    node1              ws://localhost:8646

  beaconRest         — Prysm Beacon REST 엔드포인트
    node0              http://localhost:3500
    node1              http://localhost:3600

  depositContractAddress — Deposit Contract 주소
                           0x4242424242424242424242424242424242424242

  feeRecipient       — block proposal EL 수수료 수령 주소 (.env FEE_RECIPIENT)
                       private key는 artifact에 포함하지 않음

  geth               — 수집 시점의 Geth 상태
    node{0,1}
      blockNumber      eth_blockNumber (hex)
      peerCount        net_peerCount (decimal)

  beacon             — 수집 시점의 Beacon 상태
    node{0,1}
      headSlot         현재 head slot
      syncDistance     sync lag (0 = fully synced)
      elOffline        EL offline 여부 (false = 정상)
      peerCount        연결된 beacon peer 수
      finalizedEpoch   finalized epoch 번호
      finalizedRoot    finalized block root hash

  validators         — 대표 validator 상태 (interop index)
    node0Validator0    validator[0] 상태 (active_ongoing = 정상)
    node1Validator32   validator[32] 상태

  prefundedAccounts  — L1 genesis에서 ETH를 받은 L2/L3 bootstrap depositor 계정
                       .env의 L2_DEPOSITOR_ADDRESS에서 수집, 실제 on-chain 잔액 기록
    [{address, roles: ["l2Depositor"], balanceEth, source: "genesis"}]
    ※ private key는 절대 포함하지 않음

  generatedAt        — 생성 시각 (ISO-8601 UTC)
}
```

---

## 4. prefundedAccounts — L2 depositor 설정

### 설계 원칙

L1은 L2 내부 역할별 주소(deployer, sequencer, batch poster 등)를 알지 않습니다.  
L1은 **L2 bootstrap depositor** 주소 하나만 genesis에서 prefund합니다.

```
L1 genesis → L2_DEPOSITOR_ADDRESS 에 L1 ETH 충전
     ↓
L2 deployment 프로젝트 → 이 계정으로 L1→L2 ETH deposit 실행
     ↓
L2 내부 → depositor가 deployer, sequencer, batch poster, validator 등에 L2 ETH 분배
```

이 구조는 L2→L3 bootstrap에도 동일하게 적용할 수 있습니다.

### .env 변수

| 변수 | 의미 | 기본값 |
|------|------|--------|
| `L2_DEPOSITOR_ADDRESS` | L1 genesis에서 ETH를 받을 depositor 주소 | (필수, 빈 값이면 스킵) |
| `L2_DEPOSITOR_PREFUND_BALANCE_ETH` | genesis에서 지급할 L1 ETH 수량 | `1000000000` |

### 규칙

- **public address만 입력** — `L2_DEPOSITOR_ADDRESS`는 공개 주소만 설정
- **private key는 L1 프로젝트에 저장하지 않음** — private key는 L2/L3 프로젝트의 `.env` 또는 secrets 파일에서 관리
- **genesis 적용 시점** — `pnpm run generate` 실행 시 genesis.json alloc에 삽입됨

> **중요:** Prefund addresses are applied at genesis generation time.  
> Changing `L2_DEPOSITOR_ADDRESS` or `L2_DEPOSITOR_PREFUND_BALANCE_ETH` after the chain has already been initialized does not update existing chain state.  
> To apply changed prefund settings, rebuild the L1 devnet from a clean state.

```bash
cd projects/ethereum-pos-docker
# .env에서 L2_DEPOSITOR_ADDRESS 설정 후:
pnpm run stop
pnpm run clean
pnpm run generate
pnpm run init
pnpm run start
pnpm run peer:connect
# finality 이후
pnpm run verify
pnpm run export:artifact
cat artifacts/l1-chain-info.json | jq '.prefundedAccounts'
```

---

## 5. L2/L3 parent chain 연결 시 주의사항

> **중요:** `l1-chain-info.json`의 endpoint는 artifact를 생성한 머신 기준 `localhost` 값이다.  
> 다른 인스턴스의 L2/L3에서 사용할 때는 해당 L1 머신에 접근 가능한 host/IP 기준으로 변환하거나,  
> L2 프로젝트의 `.env` override를 사용해야 한다.

### endpoint 선택 가이드

| 용도 | 권장 endpoint |
|------|--------------|
| L2 HTTP 연결 (기본) | `executionRpc.node0` |
| L2 WebSocket 연결 (구독, event polling) | `executionWs.node0` |
| Beacon 상태 조회 | `beaconRest.node0` |

- Nitro 계열 parent chain 연결에서는 `executionRpc` 또는 `executionWs` 중 하나를 사용합니다.
- L1/L2/L3가 서로 다른 인스턴스에서 동작할 경우, `localhost`를 L2 인스턴스에서 접근 가능한 IP/DNS로 변환해야 합니다.

---

## 6. 시스템 컨트랙트 주소에 대해

L2/L3 배포 시 필요한 시스템 컨트랙트 주소(RollupCore, Bridge, Inbox, Outbox 등)는  
이 artifact에 포함되지 않습니다.

```
[현재 단계] L1 chain-info: RPC, Deposit Contract, prefund 주소
[다음 단계] L2 배포 후:  RollupCore, Bridge, Inbox 등 주소 수집
```

시스템 컨트랙트 주소는 Nitro/Orbit 배포(`pnpm run deploy` 등) 완료 후 별도로 수집합니다.  
L1 artifact에 강제로 포함하지 않습니다.

---

## 7. 성공 기준

```bash
pnpm run export:artifact
```

출력 마지막 줄에서 확인:

```json
{
  "chainId": 1111,
  "finalizedEpoch": "3",
  "prefundedAccounts": 10
}
```

- `finalizedEpoch` > 0 이면 finality 달성 확인
- `prefundedAccounts`가 비어 있으면 `.env`에 `L2_*_ADDRESS`가 설정되지 않은 것 (parent L1 용도라면 설정 권장)

---

## 8. gitignore 정책

| 파일 | 커밋 여부 | 이유 |
|------|-----------|------|
| `artifacts/l1-chain-info.json` | X (gitignore) | 런타임 생성, 환경마다 다름 |
| `artifacts/l1-chain-info.example.json` | O | 구조 참조용 예시 |
| `artifacts/README.md` | O | 디렉토리 설명 |
