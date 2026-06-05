# rpc-security.md — RPC 포트 보안

---

## 포트 바인딩 정책

| 서비스 | 포트 | 바인딩 | 외부 접근 |
|--------|------|--------|-----------|
| Geth HTTP RPC | 8545 | `0.0.0.0` | 허용 (eth,net,web3,txpool만) |
| Geth WS RPC | 8546 | `0.0.0.0` | 기본 비활성 |
| Geth P2P | 30303 | `0.0.0.0` | 허용 (node0↔node1) |
| **Geth authrpc** | **8551** | **`127.0.0.1`** | **금지** |
| Prysm Beacon REST | 3500 | `0.0.0.0` | 허용 |
| Prysm Beacon gRPC | 4000 | `127.0.0.1` | 금지 (validator 전용) |
| Prysm Beacon P2P TCP | 13000 | `0.0.0.0` | 허용 (node0↔node1) |
| Prysm Beacon P2P UDP | 12000 | `0.0.0.0` | 허용 |
| **Prysm Validator gRPC** | **7000** | **`127.0.0.1`** | **금지** |
| **Prysm Validator API** | **7500** | **`127.0.0.1`** | **금지** |

---

## Geth HTTP RPC 노출 API

`--http.api=eth,net,web3,txpool` 만 허용합니다.

절대 추가하지 않는 API:
- `debug` — 내부 상태 dump, 체인 재구성 가능
- `admin` — peer 추가/제거, 노드 중지 가능
- `personal` — 계정 잠금 해제, 키 노출 가능
- `miner` — PoW 채굴 설정 (PoS에서 불필요)

---

## Engine API (authrpc) 보안

Geth authrpc (`--authrpc.addr=127.0.0.1`)는 beacon chain과의 Engine API 통신에만 사용됩니다.

- 외부 공개 시 악의적 beacon이 블록 제안을 조작할 수 있습니다
- `--authrpc.vhosts=localhost` 설정으로 vhost 기반 추가 제한
- JWT 인증 (`--authrpc.jwtsecret`) 필수

---

## Validator API 보안

Validator의 gRPC (7000)와 REST API (7500)는 validator 키 관리 및 서명을 담당합니다.

- 외부 공개 시 validator key 서명 요청이 가능해짐
- 반드시 `127.0.0.1`에만 바인딩
- 필요 시 SSH 터널을 통해 원격 접근

---

## 방화벽 설정 예시 (ufw)

```bash
# 외부 접근 허용 포트
ufw allow 22/tcp            # SSH
ufw allow 8545/tcp          # Geth HTTP RPC
ufw allow 30303/tcp         # Geth P2P
ufw allow 30303/udp         # Geth P2P
ufw allow 3500/tcp          # Prysm Beacon REST
ufw allow 13000/tcp         # Prysm Beacon P2P
ufw allow 12000/udp         # Prysm Beacon P2P

# 나머지 차단
ufw default deny incoming
ufw enable
```

---

## RPC 접근 제한 (IP 기반)

Geth HTTP RPC를 특정 IP 대역에서만 접근 가능하도록:

```bash
# 특정 IP만 허용
ufw allow from <trusted-ip> to any port 8545 proto tcp
ufw deny 8545/tcp

# Arbitrum L2 노드 IP만 허용 (필요 시)
ufw allow from <arbitrum-node-ip> to any port 8545 proto tcp
```

---

## Beacon REST API 접근 제한

외부에서 beacon 상태를 읽어야 하는 경우(예: 모니터링 툴):

```bash
ufw allow from <monitor-ip> to any port 3500 proto tcp
ufw deny 3500/tcp  # 기본 차단
```

Arbitrum L2 orbit chain은 실행 클라이언트 RPC만 사용하므로 beacon REST는 내부에서만 접근해도 됩니다.

---

## systemd 서비스 권한 정책

| 항목 | 설정값 | 위치 |
|------|--------|------|
| 서비스 실행 사용자 | `User=ethereum` | service 파일 |
| 서비스 실행 그룹 | `Group=ethereum` | service 파일 |
| 데이터 디렉토리 소유 | `ethereum:ethereum` (chown -R) | `04-install-systemd-services.sh` |
| jwtsecret 권한 | `640` (ethereum:ethereum) | `04-install-systemd-services.sh` |
| env 파일 권한 | `640` (root:ethereum) | `04-install-systemd-services.sh` |

`03-init-geth.sh`은 root로 실행되므로 chaindata가 root 소유로 생성됩니다.
`04-install-systemd-services.sh`의 `chown -R`이 이를 ethereum:ethereum으로 수정합니다.
**따라서 `install:services`는 반드시 `init` 이후에 실행해야 합니다.**

---

## WebSocket 기본 비활성

Geth WS RPC는 기본적으로 비활성 상태입니다.

- 기본값: `GETH_WS_ENABLED=false` (env sample 설정)
- 활성화: `.env`에 `GETH_WS_ENABLED=true` 설정 후 `sudo npm run install:services`
- `geth-wrapper.sh`이 `GETH_WS_ENABLED=true`일 때만 `--ws` 플래그를 추가합니다

---

## 보안 체크리스트

- [ ] `authrpc`가 `127.0.0.1`에 바인딩됨 (env: `GETH_AUTHRPC_ADDR=127.0.0.1`)
- [ ] validator API가 `127.0.0.1`에 바인딩됨 (service 파일 하드코딩)
- [ ] `http.api`에 `debug`, `admin`, `personal` 없음 (geth-wrapper.sh 고정)
- [ ] jwtsecret 파일 권한 `640` (ethereum:ethereum)
- [ ] 방화벽에서 8551, 4000, 7000, 7500 차단됨
- [ ] `GETH_WS_ENABLED=false` (기본값 확인)
