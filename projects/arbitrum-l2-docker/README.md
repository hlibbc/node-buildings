# arbitrum-l2-docker

Arbitrum Nitro L2 devnet — single sequencer simple mode, external L1.

`projects/ethereum-pos-docker`의 L1 artifact를 parent chain으로 사용하여 Arbitrum Nitro L2를 구동합니다.

**상세 runbook**: [docs/arbitrum-l2-docker/runbook.md](../../docs/arbitrum-l2-docker/runbook.md)

---

## 설계 원칙

- **L2 genesis prefund 금지.** L2 ETH는 반드시 L1→L2 deposit 플로우로만 공급. L3도 동일.
- **single sequencer simple mode.** 단일 `sequencer` 컨테이너가 sequencer + delayed-sequencer + batch-poster + staker 역할을 겸함.
- **별도 `validation_node`, `poster`, `staker`, `redis` 서비스 없음.**
- **L1 geth/beacon 서비스 없음.** L1은 외부 `ethereum-pos-docker` 프로젝트에서 별도 운용. L2 docker-compose에 geth 추가 금지.
- **private key artifact 포함 금지.** 모든 artifact에 public address만 포함. 생성 직후 자동 검증.
- **`sequencer_config.json` 커밋 금지.** 런타임 private key를 포함하므로 `.gitignore`에 등록됨.
- **staker.enable=true 고정.** staker 비활성화 fallback 허용하지 않음.

---

## 파일 복사 흐름

```
ethereum-pos-docker/artifacts/l1-chain-info.json
        │  cp
        ▼
arbitrum-l2-docker/config/l1-chain-info.json    ← L2가 읽는 L1 parent config

arbitrum-l2-docker/artifacts/l2-chain-info.json
        │  cp  (향후)
        ▼
arbitrum-l3-docker/config/l2-chain-info.json    ← L3가 읽는 L2 parent config
```

---

## ETH 공급 흐름

```
[L1 genesis]   L2_DEPOSITOR  = 1,000,000,000 ETH  (ethereum-pos-docker prefund)
[fund:l1]      depositor → deployer/batchPoster/validator = 1,000 ETH each  (L1)
[deploy]       deployer가 L1에 rollup contracts 배포
[start]        L2 sequencer 기동
[deposit]      depositor L1 → depositor L2 = 500,000,000 ETH  (Inbox.depositEth)
[distribute]   depositor L2 → role accounts = 1,000 ETH each (testUser 100 ETH)
```

---

## 빠른 시작

### 사전 조건

```bash
# L1 실행 후 artifact 복사
cp ../ethereum-pos-docker/artifacts/l1-chain-info.json ./config/l1-chain-info.json

# 의존성 설치
pnpm install

# env 준비
cp .env.sample .env
# .env 편집: DEPOSITOR/DEPLOYER/ROLLUP_OWNER/SEQUENCER/BATCH_POSTER/VALIDATOR key+address 설정
```

### 전체 실행 (자동)

```bash
pnpm run up
```

> `up` = check → load:l1 → fund:l1 → config:chain → deploy → config:node → start → deposit → distribute → verify → export:artifact

### 단계별 실행

```bash
pnpm run check           # 요구사항 확인
pnpm run load:l1         # L1 config 로드 및 검증
pnpm run fund:l1         # L1 role 계정 자금 조달 (deployer/batchPoster/validator)
pnpm run config:chain    # L2 chain config 생성
pnpm run deploy          # L1에 rollup contracts 배포
pnpm run config:node     # sequencer_config.json 생성
pnpm run start           # L2 sequencer 기동
pnpm run deposit         # L1 → L2 ETH deposit
pnpm run distribute      # L2 ETH role 계정 배분
pnpm run verify          # 전체 동작 검증
pnpm run export:artifact # L2 artifact 생성 (향후 L3 parent config용)
```

---

## 명령 요약

| 명령 | 생성 파일 | 수행 chain 동작 |
|------|-----------|-----------------|
| `check` | — | 환경/key/파일 검증 |
| `load:l1` | `resolved-l1-config.env` | L1 RPC 연결, chainId/depositor 확인 |
| `fund:l1` | `artifacts/fund-l1-accounts.json` | L1 ETH: depositor → deployer/batchPoster/validator |
| `config:chain` | `config/l2_chain_config.json` | — |
| `deploy` | `artifacts/deployment.json`, `config/l2_chain_info.json` | L1: rollup/system contracts 배포 |
| `config:node` | `config/sequencer_config.json` | L1 batchPoster/validator 잔액 확인 |
| `start` | `artifacts/l2-start.json` | L2 sequencer 기동, block 생성 확인 |
| `deposit` | `artifacts/deposit-l1-to-l2.json` | L1→L2: Inbox.depositEth |
| `distribute` | `artifacts/fund-l2-accounts.json` | L2 ETH: depositor → role accounts |
| `verify` | — | L1/L2 contract/event/block 검증 |
| `export:artifact` | `artifacts/l2-chain-info.json` | L3 parent config용 artifact 생성 |
| `stop` | — | sequencer 중지 (데이터 유지) |
| `clean` | — | 컨테이너/config/artifact 정리 |

---

## 재시작 / 중지 / 초기화

```bash
pnpm run stop                   # 중지 (체인 데이터 유지)
pnpm run start                  # 재시작
pnpm run clean                  # config/artifacts 정리 (volume 유지)
pnpm run clean -- --volumes     # 전체 초기화 (체인 데이터 포함)
pnpm run distribute -- --force  # L2 ETH 강제 재배분
```

---

## 포트

| 서비스 | host 포트 | 용도 |
|--------|-----------|------|
| L2 HTTP RPC | 8547 | L2 JSON-RPC |
| L2 WS RPC | 8548 | L2 WebSocket |
| L2 Feed | 9642 | Sequencer feed (L3 parent feed 용) |

---

## Artifacts

| 파일 | 생성 시점 | 용도 |
|------|-----------|------|
| `config/l1-chain-info.json` | 사용자가 복사 | L1 devnet 연결 정보 (gitignored) |
| `config/sequencer_config.json` | `config:node` | sequencer 런타임 config (private key 포함 — gitignored) |
| `artifacts/fund-l1-accounts.json` | `fund:l1` | L1 role 자금 조달 결과 (gitignored) |
| `artifacts/deployment.json` | `deploy` | L1 컨트랙트 주소 |
| `artifacts/l2-start.json` | `start` | sequencer 기동 시점 (l1BlockAtStart 포함 — gitignored) |
| `artifacts/deposit-l1-to-l2.json` | `deposit` | L1→L2 deposit 결과 |
| `artifacts/fund-l2-accounts.json` | `distribute` | L2 ETH 배분 결과 |
| `artifacts/l2-chain-info.json` | `export:artifact` | **L3 parent chain config용** |

---

## 디렉터리 구조

```
arbitrum-l2-docker/
├── docker-compose.yaml
├── .env.sample
├── package.json
├── rollupcreator/
│   └── Dockerfile
├── config/
│   └── l1-chain-info.json        ← 사용자가 복사 (gitignored)
├── artifacts/
└── scripts/
    ├── lib/common.sh
    ├── js/
    │   ├── fund-l1-accounts.js   ← L1 role 자금 조달
    │   ├── deposit.js            ← L1→L2 deposit
    │   └── distribute.js         ← L2 ETH 배분
    ├── 00-check-requirements.sh
    ├── 01-load-l1-config.sh
    ├── 02-fund-l1-role-accounts.sh
    ├── 02-render-chain-config.sh
    ├── 03-deploy-rollup.sh
    ├── 04-render-node-configs.sh
    ├── 05-start-l2.sh
    ├── 06-deposit-eth-to-l2.sh
    ├── 07-distribute-l2-eth.sh
    ├── 08-verify.sh
    ├── 09-export-artifact.sh
    ├── 10-stop.sh
    └── 11-clean.sh
```

---

## 문서

→ [docs/arbitrum-l2-docker/runbook.md](../../docs/arbitrum-l2-docker/runbook.md) — 최초 실행 runbook (전 단계 상세)
