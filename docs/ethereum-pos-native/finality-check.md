# finality-check.md — finality 검증 명령

---

## 검증 모드 선택

| 모드 | 명령 | 용도 |
|------|------|------|
| **기본 (최종 성공 기준)** | `npm run verify` | 2-node peer 연결 후 최종 검증 |
| **smoke test (node0 단독)** | `npm run verify -- --allow-waiting --single-node` | node0 기동 확인, peer/finality 미달성 WARN |
| **기동 중 대기** | `npm run verify -- --allow-waiting` | 서비스 시작 후 아직 finality 달성 전 확인용 |

> **단독 노드에서 finality는 달성할 수 없습니다.**
> `--single-node` 통과 = 기동 정상. peer 연결 + 2-node 구성 후 기본 모드로 최종 검증하세요.
>
> 상세 절차 → [smoke-test-node0.md](./smoke-test-node0.md)

---

## 검증 스크립트 실행

```bash
# 2-node 최종 검증 (기본 모드)
npm run verify

# node0 단독 smoke test
npm run verify -- --allow-waiting --single-node
```

→ `09-verify-finality.sh` 실행. 전체 항목을 자동 검증합니다.

---

## 수동 검증 명령

### Geth 상태

```bash
# chain ID
curl -s -X POST http://localhost:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq .

# 현재 block number
curl -s -X POST http://localhost:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq .

# peer count
curl -s -X POST http://localhost:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq .
```

### Beacon 노드 상태

```bash
# 노드 health
curl -s -o /dev/null -w "%{http_code}" http://localhost:3500/eth/v1/node/health
# 기대값: 200 (synced) 또는 206 (syncing)

# 현재 slot / epoch / sync 상태
curl -s http://localhost:3500/eth/v1/node/syncing | jq .

# peer 수
curl -s http://localhost:3500/eth/v1/node/peers | jq '.data | length'
```

### Finality Checkpoint

```bash
curl -s http://localhost:3500/eth/v1/beacon/states/head/finality_checkpoints | jq .
```

기대 출력:
```json
{
  "data": {
    "previous_justified": { "epoch": "2", "root": "0x..." },
    "current_justified":  { "epoch": "3", "root": "0x..." },
    "finalized":          { "epoch": "2", "root": "0x..." }
  }
}
```

- `finalized.epoch > 0` 이면 finality 달성
- 첫 finality는 약 2~3 epoch (SLOTS_PER_EPOCH=32, SECONDS_PER_SLOT=12 기준 약 12분)
- peer 없이는 달성 불가

### Finalized Block Header

```bash
curl -s http://localhost:3500/eth/v1/beacon/headers/finalized | jq .
```

```json
{
  "data": {
    "root": "0x...",
    "header": {
      "message": {
        "slot": "96",
        "proposer_index": "12",
        "parent_root": "0x...",
        "state_root": "0x...",
        "body_root": "0x..."
      }
    }
  }
}
```

- `slot > 0` 이면 finalized block 존재

### Validator 상태

```bash
# 특정 validator 상태
curl -s http://localhost:3500/eth/v1/beacon/states/head/validators/0 | jq .data.status
# 기대값: "active_ongoing"

# validator 범위 조회 (node0: 0~31)
curl -s "http://localhost:3500/eth/v1/beacon/states/head/validators?id=0,1,31" | jq '.data[].status'

# active validator 수
curl -s http://localhost:3500/eth/v1/beacon/states/head/validators | \
  jq '[.data[] | select(.status == "active_ongoing")] | length'
# 기대값: 64
```

---

## Finality 달성 타임라인

| 경과 | 기대 상태 |
|------|-----------|
| 0 ~ 1분 | genesis 블록 생성, slot 진행 시작 |
| 1 ~ 4분 | attestation 수집 (epoch 0~1) |
| 4 ~ 8분 | 첫 epoch 완료, justified 시작 |
| 6 ~ 12분 | finalized epoch > 0 달성 |

> peer 연결이 없으면 finality 달성 불가.

---

## Restart 후 데이터 유지 확인

```bash
# 재시작 전 block number 기록
BEFORE=$(curl -s -X POST http://localhost:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')

# 재시작
sudo npm run stop
sudo npm run start

# 재시작 후 block number
sleep 15
AFTER=$(curl -s -X POST http://localhost:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')

echo "Before: $BEFORE / After: $AFTER"
# AFTER >= BEFORE 이어야 함
# AFTER < BEFORE 이면 데이터 손실 (force-clear-db 사용 여부 확인)

# chaindata 존재 확인
ls -la /var/lib/ethereum-pos-native/geth/geth/chaindata/
ls -la /var/lib/ethereum-pos-native/prysm-beacon/beaconchaindata/
```

---

## 문제 해결

| 증상 | 확인 명령 | 가능한 원인 |
|------|-----------|-------------|
| finalized epoch 계속 0 | `net_peerCount` | peer 없음 |
| blockNumber 증가 없음 | beacon 로그 확인 | beacon-geth Engine API 연결 실패 |
| beacon health 503 | `journalctl -u eth-pos-beacon-*` | jwtsecret 불일치 또는 Geth 미실행 |
| validator offline | validator 로그 | beacon gRPC 포트 4000 연결 실패 |
| slot 진행 없음 | genesis.ssz SHA256 확인 | genesis.ssz 불일치 |
