# ethereum-pos-docker 문서

Geth + Prysm Docker Compose 2-node PoS devnet.

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [setup.md](./setup.md) | 단계별 구축 절차, 포트 정책, peer 연결 |
| [differences-from-native.md](./differences-from-native.md) | native 프로젝트와의 차이점 |
| [deposit-contract.md](./deposit-contract.md) | Ethereum PoS Deposit Contract와 devnet stub이 필요한 이유 |
| [prefund-accounts.md](./prefund-accounts.md) | genesis 단계에서 테스트/운영 주소에 ETH를 미리 충전하는 방법 |
| [l1-chain-artifact.md](./l1-chain-artifact.md) | L2/L3 Docker가 참조할 L1 chain-info artifact 설명 |

---

## 핵심 차이 (native vs docker)

| 항목 | native | docker |
|------|--------|--------|
| 실행 환경 | Ubuntu Linux | Mac / Linux Docker |
| 서비스 관리 | systemd | docker compose |
| authrpc 바인딩 | 127.0.0.1 | 0.0.0.0 (Docker 내부 전용) |
| peer 통신 | 실제 IP/ENR | 컨테이너 이름 DNS |
| config 경로 | /etc/ethereum-pos-native/ | ./config/ (bind mount) |
| 데이터 경로 | /var/lib/ethereum-pos-native/ | Docker named volumes |
| Prysm 이미지 소스 | OffchainLabs/prysm 바이너리 | gcr.io/prysmaticlabs/prysm |

상세 내용 → [differences-from-native.md](./differences-from-native.md)
