# arbitrum-parent-readiness.md — Arbitrum L2 parent chain 준비 상태

이 devnet을 Arbitrum Orbit L2의 L1 parent chain으로 사용하기 위한 사전 요건 및 현황.

---

## L1 체인 기본 정보

| 항목 | 값 |
|------|-----|
| Chain ID | 1111 |
| Network ID | 1111 |
| 체인 이름 | eth-pos-devnet |
| Consensus | Ethereum PoS (Prysm beacon chain) |
| Execution fork | Cancun / Deneb |
| genesis TTD | 0 (PoS from genesis) |
| SECONDS_PER_SLOT | 12초 |
| SLOTS_PER_EPOCH | 32 |
| 예상 블록 타임 | ~12초 |

---

## 엔드포인트 (운영 중 채워야 함)

| 엔드포인트 | 주소 | 설명 |
|-----------|------|------|
| Execution HTTP RPC | `http://<NODE0_HOST>:8545` | Arbitrum rollup이 L1 RPC로 사용 |
| Execution HTTP RPC (node1) | `http://<NODE1_HOST>:8545` | 이중화용 (선택) |
| Beacon REST API | `http://<NODE0_HOST>:3500` | 슬롯/finality 조회용 |

---

## Prefunded Deployer

`config/prefund.json`에 설정한 주소가 genesis alloc에 포함됩니다.

```bash
# 잔액 확인
curl -s -X POST http://<NODE0_HOST>:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getBalance","params":["<deployer-address>","latest"],"id":1}' \
  | jq .result
```

---

## Finality 확인 결과

> 실제 운영 후 이 섹션을 채우세요.

| 항목 | 기대값 | 실제 확인 값 |
|------|--------|------------|
| finalized epoch | > 0 | 미확인 (운영 전) |
| finalized block slot | > 0 | 미확인 |
| 첫 finality 달성 시간 | 6~12분 | 미확인 |
| 재시작 후 finality 이어짐 | 예 | 미확인 |

finality 확인 명령:
```bash
curl -s http://localhost:3500/eth/v1/beacon/states/head/finality_checkpoints | jq .data.finalized
```

---

## Peer 연결 확인 결과

> 실제 운영 후 이 섹션을 채우세요.

| 항목 | 기대값 | 실제 확인 값 |
|------|--------|------------|
| Geth peerCount | ≥ 1 | 미확인 |
| Beacon peers | ≥ 1 | 미확인 |

---

## Restart 검증 결과

> 실제 운영 후 이 섹션을 채우세요.

| 항목 | 기대값 | 결과 |
|------|--------|------|
| 재시작 후 blockNumber ≥ 재시작 전 | 예 | 미확인 |
| chaindata 보존 | 예 | 미확인 |
| finality checkpoint 이어짐 | 예 | 미확인 |
| force-clear-db 없음 | 없음 | 없음 (서비스 파일 확인됨) |

---

## Arbitrum Orbit L2로 사용하기 위한 다음 작업

### 필수 사항

1. **Rollup 컨트랙트 배포**
   - Arbitrum Nitro `RollupCreator` 컨트랙트를 L1에 배포
   - 배포 주소: prefund.json에 설정한 deployer address 사용
   - 필요 잔액: 컨트랙트 배포 비용 (가스비)

2. **AnyTrust 또는 Rollup 선택**
   - 개발 환경: AnyTrust (낮은 비용)
   - 운영 환경: Classic Rollup (높은 보안)

3. **Sequencer 설정**
   - Sequencer 주소 준비 (별도 private key)
   - `sequencerInbox` 컨트랙트 배포

4. **Validator 설정**
   - L2 Validator 주소 준비
   - L1 rollup 컨트랙트에 Validator 등록

5. **Nitro 노드 실행**
   - `--l1.url=http://<NODE0_HOST>:8545`
   - `--l1.beacon-url=http://<NODE0_HOST>:3500` (Nitro v3+ 필요)
   - `--chain.id=<L2_CHAIN_ID>`

### Arbitrum Nitro 요구사항 확인

| 요건 | 이 devnet 상태 |
|------|----------------|
| EIP-1559 | O (Geth London+) |
| EIP-4399 (PREVRANDAO) | O (Bellatrix+) |
| EIP-4788 (Beacon Root) | O (Cancun) |
| EIP-4844 (Blob 트랜잭션) | O (Cancun/Deneb) |
| Engine API v2+ | O (Geth 1.14+) |
| Beacon REST API | O (Prysm 3500) |
| Finality checkpoint 조회 | O |

---

## 현재 한계 및 제약

| 항목 | 현황 |
|------|------|
| Validator 방식 | Interop (결정론적 BLS 키) — 운영 배포용 아님 |
| 키 보안 | BLS 키가 메모리에만 존재, HSM/외부 서명자 미지원 |
| 네트워크 | 2-node 구성, 단일 지역 장애 허용성 없음 |
| 모니터링 | 기본 로그만, Grafana/Prometheus 미구성 |
| Archive 노드 | 미구성 (Arbitrum 검증자가 필요할 수 있음) |
| Blob 저장소 | Cancun 이후 EIP-4844 blob은 ~4096 slot 후 삭제 |

---

## Unresolved Issues

**Prysm 실기동 검증 필요 (Native Linux instance 기준)**
- [ ] `prysmctl testnet generate-genesis --fork=deneb` Prysm 최신 stable에서 정상 실행 여부 확인
  - 최신 Prysm이 `--fork=deneb`를 지원하지 않으면 `--fork=electra` 등으로 조정 필요
- [ ] `beacon-chain --help | grep interop` — interop 모드 플래그명 최신 stable에서 확인
- [ ] `beacon ENR`에 외부 접근 가능 IP 정상 광고 여부 (`P2P_ADVERTISE_IP` 적용 후 `npm run peer:info` 확인)
- [ ] Debian 12에서 Ubuntu PPA (jammy) 기반 geth 설치 성공 여부

**Arbitrum L2 연동 검증 필요**
- [ ] interop 모드 validator의 실제 fee recipient 동작 확인 필요
- [ ] Nitro v3+의 L1 beacon URL 요구사항 확인 (EIP-4844 blob fetching)
- [ ] 2-node 구성에서 한 노드 다운 시 L2 sequencer 영향 분석
- [ ] `GENESIS_DELAY=15` 설정과 Nitro genesis block timestamp 간 호환성 확인
- [ ] Chain ID 1111이 다른 테스트넷과 충돌하지 않는지 확인 (격리 환경 전제)
