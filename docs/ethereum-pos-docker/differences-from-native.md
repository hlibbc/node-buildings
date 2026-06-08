# differences-from-native.md — native vs docker 차이점

`ethereum-pos-native`와 `ethereum-pos-docker`의 구조적 차이를 정리합니다.

---

## 실행 환경

| 항목 | native | docker |
|------|--------|--------|
| 대상 OS | Ubuntu 22.04+ / Debian 12+ | Mac / Linux (Docker Engine) |
| 서비스 관리 | systemd | docker compose |
| 바이너리 설치 | apt / GitHub release binary | Docker 이미지 (gcr.io/prysmaticlabs) |
| 프로세스 격리 | OS 프로세스 | Docker 컨테이너 |

---

## authrpc 바인딩 차이

가장 중요한 설계 차이입니다.

| | native | docker |
|-|--------|--------|
| Geth authrpc bind | `127.0.0.1:8551` | `0.0.0.0:8551` (컨테이너 내부) |
| Geth authrpc host publish | 없음 | 없음 (ports에 미포함) |
| beacon → geth 연결 | `http://127.0.0.1:8551` | `http://geth-node0:8551` |

- **native**: beacon과 geth가 같은 호스트이므로 localhost 연결
- **docker**: 각자 다른 컨테이너이므로 Docker DNS 이름으로 연결
- 둘 다 authrpc는 외부에서 접근 불가

---

## config 파일 관리

| 항목 | native | docker |
|------|--------|--------|
| 위치 | `/etc/ethereum-pos-native/` | `./config/` (bind mount) |
| 공유 방법 | node1에 scp로 복사 | 같은 `./config/` 마운트 |
| 생성 위치 | node0 서버에서 직접 | 로컬 host (Docker run) |

Docker는 같은 머신에서 양쪽 노드가 동일한 `./config/` 를 `read-only` 로 마운트합니다.
native는 두 물리 인스턴스가 있어서 scp로 config를 복사해야 합니다.

---

## 데이터 경로

| 항목 | native | docker |
|------|--------|--------|
| Geth data | `/var/lib/ethereum-pos-native/geth` | Docker 볼륨 `geth-node0-data` |
| Beacon data | `/var/lib/ethereum-pos-native/prysm-beacon` | Docker 볼륨 `beacon-node0-data` |
| Validator data | `/var/lib/ethereum-pos-native/prysm-validator` | Docker 볼륨 `validator-node0-data` |

---

## Prysm 이미지 소스

| 항목 | native | docker |
|------|--------|--------|
| 소스 | `OffchainLabs/prysm` GitHub binary | `gcr.io/prysmaticlabs/prysm` Docker 이미지 |
| 이유 | Arbitrum 호환성 검증 binary | Docker 공식 이미지 (OffchainLabs Docker 이미지 미제공) |

---

## peer 연결 방식

| 항목 | native | docker |
|------|--------|--------|
| Geth peer 주소 | 실제 인스턴스 IP | 컨테이너 이름 (`geth-node0:30303`) |
| Beacon peer ENR IP | 인스턴스 실제 IP (`P2P_ADVERTISE_IP`) | 컨테이너 내부 IP (Docker DNS 자동 처리) |
| peer 연결 스크립트 | `11-print-peer-info.sh` | `06-peer-connect.sh` (자동화) |

Docker는 같은 bridge network에 있으므로 컨테이너 이름으로 서로 찾을 수 있습니다.
native는 실제 IP가 필요하고 `P2P_ADVERTISE_IP` 설정이 필요합니다.

---

## 서비스 의존성

| | native | docker |
|-|--------|--------|
| geth → beacon | 순서 보장 (start 스크립트) | `depends_on: geth-node0` |
| beacon → validator | 순서 보장 (start 스크립트) | `depends_on: beacon-node0` |
| 재시작 정책 | systemd `Restart=on-failure` | `restart: unless-stopped` |
| 로그 | journald (`journalctl -u`) | docker logs (`docker compose logs`) |

---

## 한계 (docker 버전)

- **단일 머신**: docker compose는 기본적으로 같은 머신에서 양쪽 노드를 실행
  (2대 인스턴스에서 실행하려면 Docker Swarm 또는 별도 설정 필요)
- **Prysm 이미지 소스**: prysmaticlabs/prysm Docker 이미지 사용 (OffchainLabs fork 아님)
- **P2P 포트**: Docker bridge network에서 beacon P2P가 제대로 동작하는지 실기동 검증 필요

---

## 언제 무엇을 쓸까

| 목적 | 권장 |
|------|------|
| Mac 로컬 실험 / 개념 검증 | `ethereum-pos-docker` |
| Ubuntu 서버 배포 | `ethereum-pos-native` |
| Arbitrum L2 parent chain | `ethereum-pos-native` (OffchainLabs prysm binary) |
| CI 환경 | `ethereum-pos-docker` |
