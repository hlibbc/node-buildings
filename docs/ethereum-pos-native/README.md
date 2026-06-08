# ethereum-pos-native 문서

Ethereum PoS private devnet (Geth + Prysm, native 2-node) 구축 및 운영 문서.

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [concepts.md](./concepts.md) | Geth·beacon·validator 구조, slot/epoch/finality, interop 키, P2P |
| [native-setup.md](./native-setup.md) | 단계별 구축 절차 (node0, node1 순서) |
| [smoke-test-node0.md](./smoke-test-node0.md) | node0 단독 smoke test 절차 및 기준 |
| [peer-connection.md](./peer-connection.md) | Geth / Prysm peer 연결, P2P_ADVERTISE_IP 설정 |
| [finality-check.md](./finality-check.md) | finality 검증 명령 및 해석 |
| [rpc-security.md](./rpc-security.md) | RPC 포트 보안 설정 및 방화벽 규칙 |
| [version-matrix.md](./version-matrix.md) | 사용 버전 기록 및 호환성, 미검증 항목 |
| [docker-plan.md](./docker-plan.md) | Docker 방식 전환 계획 (미구현) |
| [arbitrum-parent-readiness.md](./arbitrum-parent-readiness.md) | Arbitrum L2 parent chain 준비 상태 |

---

## 프로젝트 위치

```
projects/ethereum-pos-native/   ← 스크립트 및 설정
docs/ethereum-pos-native/       ← 이 문서들
```

---

## 성공 기준 요약

- [ ] node0, node1 각각 Geth + beacon + validator 실행
- [ ] 동일한 genesis.json / genesis.ssz / jwtsecret 사용
- [ ] node0 validator 0~31, node1 validator 32~63 (중복 없음)
- [ ] Geth 블록 증가 확인
- [ ] Prysm slot / epoch 진행 확인
- [ ] finalized checkpoint 조회 성공
- [ ] node0 ↔ node1 peer 연결
- [ ] 재시작 후 데이터 유지 확인
