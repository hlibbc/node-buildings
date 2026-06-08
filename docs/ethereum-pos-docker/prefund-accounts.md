# Prefund Accounts

genesis.json 생성 시 특정 주소에 ETH를 미리 충전하는 방법과 그 목적을 설명합니다.

---

## 1. Prefund란

Ethereum genesis 블록에서 특정 EVM 주소에 ETH 잔액을 미리 할당하는 설정입니다.  
`genesis.json`의 `alloc` 필드에 주소와 wei 잔액을 지정하면, 체인 기동 시점부터 해당 주소가 ETH를 보유합니다.

```json
"alloc": {
    "1111111111111111111111111111111111111111": {
        "balance": "0x21e19e0c9bab2400000"
    }
}
```

---

## 2. 왜 L2/L3 주소를 미리 충전하는가

이 devnet은 L2/L3 스택(Arbitrum Nitro/Orbit)의 parent chain으로 사용됩니다.  
L2/L3 기동 시 여러 역할이 L1에 가스를 소비하며, 각 역할별로 별도의 EVM 주소가 필요합니다.

```
L1 devnet (이 프로젝트)
  ├── l1-deployer       ← L2 컨트랙트 배포 (RollupCreator 등)
  ├── l1-fee-recipient  ← L1 block proposal 수수료 수령
  ├── l2-deployer       ← L2 체인 내 컨트랙트 배포
  ├── l2-sequencer      ← L2 트랜잭션 시퀀싱, L1 inbox 제출
  ├── l2-batch-poster   ← L2 배치 데이터 L1 포스팅
  ├── l2-validator      ← L2 assertion 제출 및 검증
  ├── l3-deployer       ← L3 컨트랙트 배포
  ├── l3-sequencer      ← L3 시퀀싱
  ├── l3-batch-poster   ← L3 배치 포스팅
  └── test-user-1       ← 테스트 트랜잭션용
```

각 역할은 운영 중 L1 가스를 소비합니다. Genesis 시점에 충전하지 않으면 첫 트랜잭션부터 잔액 부족 오류가 발생합니다.

---

## 3. Validator BLS key와 EVM 주소의 차이

prefund 대상은 **Execution Layer EVM 주소**입니다. Validator BLS key와 다릅니다.

| 구분 | 타입 | 용도 |
|------|------|------|
| Validator BLS key | BLS12-381 키 쌍 | Consensus Layer 서명 (attestation, block proposal) |
| EVM 주소 | secp256k1 기반 | Execution Layer 트랜잭션, 가스 지불, 컨트랙트 배포 |

이 devnet의 validator는 `--interop-*` 옵션으로 자동 생성됩니다.  
BLS key를 EVM 주소로 변환하거나 private key를 파일에 저장하지 마세요.

---

## 4. FEE_RECIPIENT와 prefund의 관계

`.env`의 `FEE_RECIPIENT`는 block proposal 시 EL 수수료(priority fee)를 받을 EVM 주소입니다.  
validator BLS key와 무관한 별도의 EVM 주소로 설정합니다.

prefund의 `l1-fee-recipient` 주소를 `FEE_RECIPIENT`로 사용하면 수수료가 genesis에서 충전된 주소로 귀속됩니다.

```bash
# .env
FEE_RECIPIENT=0x2222222222222222222222222222222222222222  # l1-fee-recipient
```

---

## 5. prefund.json 작성법

```bash
cp config/prefund.json.example config/prefund.json
# 실제 운영 주소로 교체 (주소만, private key 저장 금지)
```

**형식**

```json
{
    "accounts": [
        {
            "name": "l1-deployer",
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

**검증 규칙** (`apply-prefund.mjs` 자동 적용)
- `address`: `0x` + 40자리 hex 형식 필수
- `balanceEth`: 양수 정수 문자열 필수 (`"10000"`, `"1"` 등)
- 중복 주소 금지
- deposit contract 주소(`0x4242...4242`)와 충돌 금지

---

## 6. 10000 ETH의 wei 표현

```
10000 ETH
  = 10000 × 10^18 wei
  = 10,000,000,000,000,000,000,000 wei
  = 0x21e19e0c9bab2400000 (hex)
```

genesis.json에는 wei hex 값이 저장됩니다.

---

## 7. 잔액 확인

체인 기동 후 prefund 결과를 검증합니다.

```bash
# l1-deployer 잔액 확인 (10000 ETH = 0x21e19e0c9bab2400000)
curl -s -X POST http://localhost:8545 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0x1111111111111111111111111111111111111111","latest"],"id":1}' \
    | jq -r '.result'
# 기댓값: 0x21e19e0c9bab2400000
```

---

## 8. 주의사항

- `config/prefund.json`은 `.gitignore`에 등록됩니다 — 실제 주소 유출 방지
- private key는 어떤 파일에도 저장하지 마세요
- `config/prefund.json.example`은 placeholder 주소(`0x1111...`, `0x2222...` 등)만 포함
- prefund는 `pnpm run generate` 단계에서 genesis.json에 주입됩니다 — 기동 중에는 변경 불가
- 주소 변경이 필요하면 `pnpm run clean && pnpm run generate`로 재생성
