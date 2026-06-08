# smoke-test-node0.md — node0 단독 smoke test

2-node peer 연결 전에 node0 단독으로 Geth + beacon + validator가 정상 기동하는지 확인하는 절차.

---

## 목적

peer 연결 설정을 진행하기 전에:
- Geth가 올바른 genesis로 초기화되었는지 확인
- beacon-chain이 genesis.ssz를 정상 로드하는지 확인
- validator가 할당된 index(0~31)를 정상 인식하는지 확인
- 블록 생성과 slot 진행이 시작되는지 확인
- 서비스가 crash 없이 안정적으로 실행되는지 확인

---

## node0 단독 smoke test vs 2-node finality

| 항목 | node0 단독 smoke test | 2-node finality 검증 |
|------|----------------------|----------------------|
| Geth 블록 생성 | **가능** | 가능 |
| beacon slot 진행 | **가능** | 가능 |
| validator active | **가능** | 가능 |
| Geth net_peerCount | 0 (단독) | ≥ 1 |
| beacon peers | 0 (단독) | ≥ 1 |
| finalized checkpoint | **불가** (32/64 validator, 2/3 quorum 미달) | **가능** |
| 최종 성공 기준 | 아님 | **이것이 최종 기준** |

> **단독 노드에서 finality는 달성할 수 없습니다.**
> validator 64개 중 32개만 참여하면 2/3 attestation quorum이 불가능합니다.
> finality는 node0 + node1이 peer 연결된 상태에서만 달성됩니다.

---

## 전제 조건

```bash
# 아래 단계가 완료되어 있어야 합니다
sudo npm run install:geth
sudo npm run install:prysm
sudo npm run generate        # node0에서만 실행
sudo npm run init
sudo npm run install:services
```

---

## 단계별 절차

### 1. 서비스 시작

```bash
sudo npm run start
```

각 서비스가 순서대로 시작됩니다: Geth → beacon → validator

---

### 2. 기본 상태 확인

```bash
sudo npm run status
```

3개 서비스가 모두 `active (running)` 상태여야 합니다:
```
[active / enabled] eth-pos-geth-eth-pos-node0
[active / enabled] eth-pos-beacon-eth-pos-node0
[active / enabled] eth-pos-validator-eth-pos-node0
```

---

### 3. smoke test 검증 실행

```bash
# node0 단독 smoke test 모드
# --allow-waiting: peer=0, finality=0 허용 (기동 직후 또는 아직 달성 전)
# --single-node:  peer=0 WARN 처리 (단독 노드 한계 명시)
npm run verify -- --allow-waiting --single-node
```

> `--allow-waiting --single-node` 동시 사용 시:
> - peer=0 → WARN (예상된 상태)
> - finality=0 → WARN (단독 노드에서 정상)
> - 블록 증가, slot 진행, validator active → PASS 여야 함

---

### 4. 로그에서 정상 동작 확인

```bash
# Geth: 블록 생성 확인
journalctl -u eth-pos-geth-eth-pos-node0 -n 30 --no-pager | \
    grep -E "Imported new chain|mined|payload"

# Beacon: slot 진행 확인
journalctl -u eth-pos-beacon-eth-pos-node0 -n 30 --no-pager | \
    grep -E "Synced new block|slot|epoch"

# Validator: attestation 확인
journalctl -u eth-pos-validator-eth-pos-node0 -n 30 --no-pager | \
    grep -E "Submitted attestation|Validator|index"
```

---

### 5. 수동 RPC 확인

```bash
# 블록 생성 확인 (값이 증가해야 함)
curl -s -X POST http://localhost:8545 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r .result

# chain ID 확인 (0x457 = 1111)
curl -s -X POST http://localhost:8545 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq -r .result

# beacon slot 확인
curl -s http://localhost:3500/eth/v1/node/syncing | jq .data.head_slot

# validator 0번 상태 확인
curl -s http://localhost:3500/eth/v1/beacon/states/head/validators/0 | jq .data.status
# 기대값: "active_ongoing"
```

---

### 6. P2P peer 정보 출력

node1과 연결하기 전에 이 노드의 peer 정보를 미리 확인합니다.

```bash
npm run peer:info
```

출력에서 확인할 사항:
- **Geth enode**: `enode://...@<IP>:30303` — IP가 loopback(127.0.0.1)이 아닌지 확인
- **beacon ENR**: `enr:-MK4Q...` — p2p_addresses에 loopback이 있으면 경고 출력됨
- ENR IP가 loopback이면 `.env`에 `P2P_ADVERTISE_IP=<인스턴스 실제 IP>` 설정 후 재기동

```bash
# P2P_ADVERTISE_IP 설정 예시
# .env에 추가:
#   P2P_ADVERTISE_IP=10.0.1.10   ← 이 인스턴스의 외부 접근 가능 IP

sudo npm run install:services
sudo npm run stop && sudo npm run start
npm run peer:info   # 다시 확인
```

---

## smoke test 통과 기준

| 항목 | 기대값 | 검증 명령 |
|------|--------|-----------|
| 서비스 3개 active | active | `npm run status` |
| Geth chain ID | 0x457 (1111) | `eth_chainId` |
| Geth blockNumber | 증가 | 15초 간격 두 번 확인 |
| beacon health | HTTP 200 or 206 | `/eth/v1/node/health` |
| beacon head_slot | 증가 | `/eth/v1/node/syncing` |
| validator[0] status | active_ongoing | `/eth/v1/beacon/states/head/validators/0` |

---

## 실패 시 확인 포인트

| 증상 | 가능한 원인 | 확인 명령 |
|------|-------------|-----------|
| geth 시작 실패 | genesis 불일치, 권한 문제 | `journalctl -u eth-pos-geth-eth-pos-node0 -n 50` |
| beacon `health 503` | geth authrpc 연결 실패 | `journalctl -u eth-pos-beacon-eth-pos-node0 -n 20` |
| validator 응답 없음 | beacon gRPC(4000) 연결 실패 | `journalctl -u eth-pos-validator-eth-pos-node0 -n 20` |
| slot=0 계속 유지 | genesis.ssz 불일치 | `sha256sum /etc/ethereum-pos-native/genesis.ssz` |
| blockNumber=0 | beacon → geth Engine API 미연결 | jwtsecret 일치 여부 확인 |

---

## smoke test 통과 후 다음 단계

smoke test 통과 = node0 단독 기동이 정상임을 확인.
이후 절차:

1. `npm run peer:info` 결과를 기록 (Geth enode, beacon ENR)
2. node1 인스턴스에서 geth/prysm 설치 및 config 복사
3. node1 `.env`에 node0 enode/ENR 설정
4. node0 `.env`에 node1 enode/ENR 설정
5. 양쪽 `install:services` 후 재시작
6. **최종 검증**: `npm run verify` (기본 모드 — peer ≥ 1, finality > 0)

→ [native-setup.md](./native-setup.md) 단계 10~11 참조
→ [peer-connection.md](./peer-connection.md) 참조
→ [finality-check.md](./finality-check.md) 참조
