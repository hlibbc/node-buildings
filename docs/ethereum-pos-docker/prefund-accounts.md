# Prefund Accounts

genesis.json 생성 시 특정 주소에 ETH를 미리 충전하는 방법과 그 목적을 설명합니다.

---

## 1. Prefund란

Ethereum genesis 블록에서 특정 EVM 주소에 ETH 잔액을 미리 할당하는 설정입니다.  
`genesis.json`의 `alloc` 필드에 주소와 wei 잔액을 지정하면, 체인 기동 시점부터 해당 주소가 ETH를 보유합니다.

```json
"alloc": {
    "1111111111111111111111111111111111111111": {
        "balance": "0xde0b6b3a7640000000000000"
    }
}
```

Prefund는 `pnpm run generate` 단계에서 genesis.json에 주입됩니다.  
체인이 이미 초기화된 이후에는 genesis를 수정해도 기존 체인 상태에 반영되지 않습니다.

---

## 2. L2/L3 parent chain bootstrap 설계

### 설계 원칙

**L1은 L2 내부 역할별 주소를 알지 않습니다.**

L1의 책임은 "L2 deposit을 실행할 충분한 L1 ETH를 가진 계정 하나를 제공하는 것"입니다.

```
L1 genesis → L2_DEPOSITOR_ADDRESS 에 L1 ETH 충전
     ↓
L2 deployment 프로젝트 → 이 계정으로 L1→L2 ETH deposit 실행
     ↓
L2 내부 → depositor가 deployer, sequencer, batch poster, validator 등 역할별 주소에 L2 ETH 분배
```

이 구조는 L2→L3 bootstrap에도 동일하게 적용됩니다.

### 역할 분리

| 계층 | 책임 |
|------|------|
| **L1 (이 프로젝트)** | `L2_DEPOSITOR_ADDRESS` 하나를 genesis에서 ETH 충전 |
| **L2 deployment 프로젝트** | depositor 계정으로 L1→L2 ETH deposit 실행 |
| **L2 deployment 프로젝트** | deployer, sequencer, batch poster, validator 등 역할별 주소에 L2 ETH 분배 |
| **L2 deployment 프로젝트** | L1에 rollup/system contracts 배포 |

---

## 3. L2_DEPOSITOR_ADDRESS 설정

### .env 변수

| 변수 | 의미 | 기본값 |
|------|------|--------|
| `L2_DEPOSITOR_ADDRESS` | L1 genesis에서 ETH를 받을 depositor 주소 | (빈 값이면 스킵) |
| `L2_DEPOSITOR_PREFUND_BALANCE_ETH` | genesis에서 지급할 L1 ETH 수량 | `1000000000` |

### 설정 방법

```bash
# .env
L2_DEPOSITOR_ADDRESS=0xYourDepositorAddressHere
L2_DEPOSITOR_PREFUND_BALANCE_ETH=1000000000
```

- **public address만 입력** — private key는 이 파일에 저장하지 않음
- **private key는 L2/L3 프로젝트의 `.env` 또는 secrets 파일에서 관리**
- `L2_DEPOSITOR_ADDRESS`가 비어 있으면 genesis alloc에 추가하지 않고 스킵

### 적용 순서

```bash
cd projects/ethereum-pos-docker

# .env에서 L2_DEPOSITOR_ADDRESS 설정 후:
pnpm run stop
pnpm run clean
pnpm run generate    # genesis alloc에 L2_DEPOSITOR_ADDRESS 자동 삽입
pnpm run init
pnpm run start
pnpm run peer:connect

# finality 달성 후
pnpm run verify      # depositor 잔액 검증 포함
pnpm run export:artifact
cat artifacts/l1-chain-info.json | jq '.prefundedAccounts'
```

### artifact 출력 예시

`pnpm run export:artifact` 결과 `artifacts/l1-chain-info.json`의 `prefundedAccounts`:

```json
"prefundedAccounts": [
    {
        "address": "0x...",
        "roles": ["l2Depositor"],
        "balanceEth": "1000000000",
        "source": "genesis"
    }
]
```

`L2_DEPOSITOR_ADDRESS`가 설정되지 않았으면 `prefundedAccounts: []`.

> **중요:** Prefund addresses are applied at genesis generation time.  
> Changing `L2_DEPOSITOR_ADDRESS` or `L2_DEPOSITOR_PREFUND_BALANCE_ETH` after the chain has already been initialized does not update existing chain state.  
> To apply changed prefund settings, rebuild the L1 devnet from a clean state.

---

## 4. config/prefund.json (optional — 일반 dev/test 계정용)

`config/prefund.json`은 일반 개발/테스트 목적의 추가 계정을 genesis에 충전할 때 사용하는 선택적 기능입니다.  
L2/L3 bootstrap 용도(`L2_DEPOSITOR_ADDRESS`)와는 별개입니다.

| 용도 | 방법 |
|------|------|
| L2/L3 bootstrap depositor | `.env`의 `L2_DEPOSITOR_ADDRESS` (권장) |
| 일반 dev/test 계정 추가 충전 | `config/prefund.json` (optional) |

### 작성 방법

```bash
cp config/prefund.json.example config/prefund.json
# 실제 주소로 교체 (주소만, private key 저장 금지)
```

**형식**

```json
{
    "accounts": [
        {
            "name": "dev-test-user",
            "address": "0x<40자리 hex>",
            "balanceEth": "10000"
        }
    ]
}
```

| 필드 | 타입 | 설명 |
|------|------|------|
| `name` | string | 역할 식별자 (로그 출력용) |
| `address` | string | EVM 주소 (`0x` + 40자리 hex) |
| `balanceEth` | string | 충전할 ETH량 (양수 정수 문자열) |

**검증 규칙** (`scripts/lib/apply-prefund.mjs` 자동 적용)

- `address`: `0x` + 40자리 hex 형식 필수
- `balanceEth`: 양수 정수 문자열 필수
- 중복 주소 금지
- deposit contract 주소(`0x4242...4242`)와 충돌 금지

`config/prefund.json`은 `.gitignore`에 등록되어 있어 실제 주소가 저장소에 포함되지 않습니다.  
`config/prefund.json.example`은 placeholder 주소만 포함합니다.

---

## 5. Validator BLS key와 EVM 주소의 차이

prefund 대상은 **Execution Layer EVM 주소**입니다. Validator BLS key와 다릅니다.

| 구분 | 타입 | 용도 |
|------|------|------|
| Validator BLS key | BLS12-381 키 쌍 | Consensus Layer 서명 (attestation, block proposal) |
| EVM 주소 | secp256k1 기반 | Execution Layer 트랜잭션, 가스 지불, 컨트랙트 배포 |

이 devnet의 validator는 `--interop-*` 옵션으로 자동 생성됩니다.  
BLS key를 EVM 주소로 변환하거나 private key를 파일에 저장하지 마세요.

---

## 6. FEE_RECIPIENT와 prefund의 관계

`.env`의 `FEE_RECIPIENT`는 block proposal 시 EL 수수료(priority fee)를 받을 EVM 주소입니다.  
validator BLS key와 무관한 별도의 EVM 주소로 설정합니다.

`config/prefund.json`에 fee recipient 주소를 포함해두면, 수수료가 genesis에서 충전된 주소로 귀속됩니다.

```bash
# .env
FEE_RECIPIENT=0x2222222222222222222222222222222222222222
```

---

## 7. ETH → wei 변환

genesis.json에는 wei hex 값이 저장됩니다.

```
1,000,000,000 ETH
  = 1000000000 × 10^18 wei
  = 1,000,000,000,000,000,000,000,000,000 wei
  = 0xde0b6b3a7640000000000000 (hex)
```

변환 확인:
```bash
node -e "console.log('0x' + (1000000000n * 10n**18n).toString(16))"
# 0xde0b6b3a7640000000000000
```

---

## 8. 잔액 확인

체인 기동 후 prefund 결과 검증:

```bash
# pnpm run verify — depositor 잔액 포함 전체 검증
pnpm run verify

# 직접 확인
curl -s -X POST http://localhost:8545 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0xYourDepositorAddress","latest"],"id":1}' \
    | jq -r '.result'
```

또는 artifact 생성 후:

```bash
pnpm run export:artifact
cat artifacts/l1-chain-info.json | jq '.prefundedAccounts'
```

---

## 9. 주의사항

- **private key는 어떤 L1 파일에도 저장하지 마세요** — `L2_DEPOSITOR_ADDRESS`는 public address만
- **private key는 L2/L3 프로젝트의 `.env` 또는 secrets 파일에서 관리**
- prefund는 `pnpm run generate` 단계에서만 genesis.json에 주입됩니다 — 기동 중에는 변경 불가
- 주소 또는 금액 변경이 필요하면 `pnpm run stop && pnpm run clean && pnpm run generate`로 재구축
- `config/prefund.json`은 `.gitignore` 등록 — 실제 주소 유출 방지
- L2 rollup deployment, system contracts 배포, L2 역할별 ETH 분배는 **L2 프로젝트가 담당**
