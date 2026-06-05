# version-matrix.md — 사용 버전 기록

---

## 버전 고정 정책

- `latest`, `stable` 태그는 사용하지 않습니다.
- 실제 설치 후 `versions.lock`에 버전 정보가 자동 기록됩니다.
- Geth: `apt-mark hold geth` 적용으로 버전 고정
- Prysm: checksums.txt SHA256 검증 후 설치
- 버전 업그레이드 시 `versions.lock` 및 이 문서를 갱신합니다.

---

## 설치 방식 요약

| 구성요소 | 설치 방식 | 릴리즈 소스 | 검증 방식 |
|----------|-----------|-------------|-----------|
| **Geth** | 공식 apt PPA | `ppa:ethereum/ethereum` | GPG 패키지 서명 (key: 8A16544F) |
| beacon-chain | GitHub release binary | `OffchainLabs/prysm` (기본) | checksums.txt 또는 .sha256 |
| validator | GitHub release binary | `OffchainLabs/prysm` (기본) | checksums.txt 또는 .sha256 |
| prysmctl | GitHub release binary | `OffchainLabs/prysm` (기본) | checksums.txt 또는 .sha256 |

> **Prysm 릴리즈 소스 변경**: `PRYSM_GITHUB_ORG=prysmaticlabs sudo npm run install:prysm`

---

## 현재 사용 버전

> 설치 후 `projects/ethereum-pos-native/versions.lock` 내용으로 채우세요.

**Geth (apt 기반)**

| 항목 | 값 |
|------|-----|
| GETH_VERSION | (versions.lock 참조) |
| GETH_APT_PACKAGE | (versions.lock 참조, apt-cache policy geth로 확인) |
| GETH_APT_SOURCE | ppa:ethereum/ethereum |
| GETH_APT_KEY_FINGERPRINT | 8A16544F |

**Prysm (binary 기반)**

| 구성요소 | 버전 | SHA256 |
|----------|------|--------|
| beacon-chain | (versions.lock 참조) | (versions.lock 참조) |
| validator | (versions.lock 참조) | (versions.lock 참조) |
| prysmctl | (versions.lock 참조) | (versions.lock 참조) |

versions.lock 조회:
```bash
cat projects/ethereum-pos-native/versions.lock

# Geth apt 설치 상세 정보
apt-cache policy geth
apt-cache show geth | grep -E "Version:|Maintainer:|Source:"
```

---

## 설치 환경

| 항목 | 값 |
|------|-----|
| OS | Ubuntu 22.04+ / Debian 12+ |
| Arch | amd64 또는 arm64 |
| systemd | v249+ |
| Geth 바이너리 | `/usr/bin/geth` (apt), `/usr/local/bin/geth` (symlink) |
| Prysm 바이너리 | `/usr/local/bin/` |

---

## Chain 설정

| 항목 | 값 |
|------|-----|
| Chain ID | 1111 |
| Network ID | 1111 |
| Network name | eth-pos-devnet |
| Consensus | PoS (Casper FFG) |
| Execution fork | Cancun (EIP-4844) |
| Beacon fork | Deneb |
| Validators | 64 (interop) |
| SECONDS_PER_SLOT | 12 |
| SLOTS_PER_EPOCH | 32 |
| Genesis TTD | 0 (PoS from genesis) |

---

## Fork 버전

| Fork | 버전 | Epoch |
|------|------|-------|
| Genesis | 0x20000089 | - |
| Altair | 0x20000090 | 0 |
| Bellatrix | 0x20000091 | 0 |
| Capella | 0x20000092 | 0 |
| Deneb | 0x20000093 | 0 |

---

## 호환성 확인 기준

- Geth 최신 stable: https://github.com/ethereum/go-ethereum/releases/latest
- Prysm 최신 stable: https://github.com/prysmaticlabs/prysm/releases/latest
- Prysm interop 모드 (BLS key 자동 생성) 지원 여부는 `validator --help | grep interop` 확인

---

## ⚠ 미검증 항목 (실기동 필요)

| 항목 | 상태 | 검증 방법 |
|------|------|-----------|
| `prysmctl testnet generate-genesis --fork=deneb` | **실기동 검증 필요** | `sudo npm run generate` 실행 후 genesis.ssz 생성 확인 |
| Prysm 최신 stable interop 모드 동작 | **실기동 검증 필요** | `validator --help \| grep interop-start-index` 확인 |
| Debian 12 + Ubuntu PPA 호환 | **실기동 검증 필요** | `/etc/apt/sources.list.d/ethereum.list` 설치 후 `apt-get install -y geth` 성공 여부 |
| beacon ENR 외부 IP 광고 (`P2P_ADVERTISE_IP`) | **실기동 검증 필요** | `npm run peer:info` 실행 후 ENR에 올바른 IP 포함 여부 확인 |

### Debian에서 Ubuntu PPA 사용 시 주의

Debian 12 (bookworm)는 Ubuntu PPA를 직접 지원하지 않습니다.
`00-install-geth.sh`는 Ubuntu jammy 패키지를 사용하므로 devnet 환경에서 동작 여부를 별도 검증해야 합니다.

- 기본 codename: `jammy` (Ubuntu 22.04)
- 변경 방법: `GETH_PPA_UBUNTU_CODENAME=noble sudo npm run install:geth`
- 검증 후 이 문서와 versions.lock에 실제 사용 codename을 기록하세요.

### Prysm generate-genesis --fork=deneb 미검증

`02-generate-network-config.sh`는 `prysmctl testnet generate-genesis --fork=deneb`를 사용합니다.

- Prysm v5.x 최신 stable에서 `--fork=deneb`가 지원되는지 실기동에서 확인 필요
- 지원하지 않을 경우 `--fork=electra` 또는 `--fork=capella` 등으로 변경 필요
- `arbitrum-parent-readiness.md`의 Unresolved Issues 참조

---

## 업그레이드 절차

```bash
# 1. 서비스 정지
sudo npm run stop

# 2. 새 버전 설치 (versions.lock 자동 갱신)
sudo npm run install:geth
sudo npm run install:prysm

# 3. 버전 확인
geth version
beacon-chain --version

# 4. 서비스 재시작 (데이터 유지)
sudo npm run start

# 5. finality 재확인
npm run verify
```

> genesis.json, genesis.ssz, config.yml은 업그레이드 시 재생성하지 않습니다.
