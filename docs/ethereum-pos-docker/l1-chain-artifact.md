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

  executionRpc       — Geth JSON-RPC 엔드포인트
    node0              http://localhost:8545
    node1              http://localhost:8645

  beaconRest         — Prysm Beacon REST 엔드포인트
    node0              http://localhost:3500
    node1              http://localhost:3600

  depositContractAddress — Deposit Contract 주소
                           0x4242424242424242424242424242424242424242

  feeRecipient       — block proposal EL 수수료 수령 주소 (.env FEE_RECIPIENT)

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

  prefundedAccounts  — prefund된 계정 목록 (config/prefund.json 기반)
    [{name, address, balanceEth}]

  generatedAt        — 생성 시각 (ISO-8601 UTC)
}
```

---

## 4. 시스템 컨트랙트 주소에 대해

L2/L3 배포 시 필요한 시스템 컨트랙트 주소(RollupCore, Bridge, Inbox, Outbox 등)는  
이 artifact에 포함되지 않습니다.

```
[현재 단계] L1 chain-info: RPC, Deposit Contract, prefund 주소
[다음 단계] L2 배포 후:  RollupCore, Bridge, Inbox 등 주소 수집
```

시스템 컨트랙트 주소는 Nitro/Orbit 배포(`pnpm run deploy` 등) 완료 후 별도로 수집합니다.  
L1 artifact에 강제로 포함하지 않습니다.

---

## 5. 성공 기준

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
- `prefundedAccounts`가 0 이면 `config/prefund.json`이 없는 것 (정상 동작, 단 L2 기동 전에 설정 권장)

---

## 6. gitignore 정책

| 파일 | 커밋 여부 | 이유 |
|------|-----------|------|
| `artifacts/l1-chain-info.json` | X (gitignore) | 런타임 생성, 환경마다 다름 |
| `artifacts/l1-chain-info.example.json` | O | 구조 참조용 예시 |
| `artifacts/README.md` | O | 디렉토리 설명 |
