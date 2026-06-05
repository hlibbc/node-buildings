# peer-connection.md — Geth / Prysm peer 연결

node0 ↔ node1 간 peer 연결 설정 방법.

---

## peer:info — 이 노드의 peer 정보 출력

peer 연결 설정 전에 이 노드의 enode/ENR을 먼저 확인합니다.

```bash
npm run peer:info
```

출력 예시:
```
Geth enode:
  raw: enode://abc123...@127.0.0.1:30303
  *** IP가 loopback — 실제 IP로 교체됨 ***
  fixed: enode://abc123...@10.0.1.10:30303

beacon ENR: enr:-MK4Q...
beacon peer_id: 16Uiu2HAmXXX...
```

**loopback IP 경고 대응** (beacon ENR 또는 Geth enode가 127.0.0.1인 경우):

```bash
# .env에 이 인스턴스의 외부 접근 가능 IP 설정
# NODE0_HOST와 동일한 값 권장
P2P_ADVERTISE_IP=10.0.1.10   # ← 실제 IP로 교체

# 서비스 반영
sudo npm run install:services
sudo npm run stop && sudo npm run start

# 다시 확인
npm run peer:info
```

> `P2P_ADVERTISE_IP` 는 beacon-wrapper.sh의 `--p2p-host-ip` 플래그에 전달됩니다.
> DNS 이름 사용: `P2P_ADVERTISE_DNS=node0.example.internal`

---

## 개요

2-node devnet에서 peer 연결이 없으면:
- Geth 블록이 한쪽에만 전파됨
- beacon chain이 단일 validator 세트로만 동작 → finality 달성 어려움
- validator attestation이 상대 노드에 전달되지 않음

peer 연결은 **두 방향** 모두 필요합니다.

---

## 필요 포트 (방화벽 허용)

| 서비스 | 프로토콜 | 포트 | 방향 |
|--------|----------|------|------|
| Geth P2P | TCP | 30303 | inbound/outbound |
| Geth P2P | UDP | 30303 | inbound/outbound |
| Prysm Beacon P2P | TCP | 13000 | inbound/outbound |
| Prysm Beacon P2P | UDP | 12000 | inbound/outbound |

방화벽 예시 (ufw):
```bash
ufw allow 30303/tcp
ufw allow 30303/udp
ufw allow 13000/tcp
ufw allow 12000/udp
```

---

## Geth peer 연결

### Step 1 — node0 enode 확인

**node0에서:**
```bash
geth attach --exec "admin.nodeInfo.enode" /var/lib/ethereum-pos-native/geth/geth.ipc
```

출력 예:
```
"enode://abc123...@127.0.0.1:30303"
```

> 출력에 `127.0.0.1`이 있으면 node0의 실제 IP로 교체해야 합니다.
> 실제 IP = `NODE0_HOST` 환경 변수 값

```
"enode://abc123...@<NODE0_HOST>:30303"
```

### Step 2 — node1의 static-nodes.json 설정

**node1에서 (Geth 정지 후):**
```bash
mkdir -p /var/lib/ethereum-pos-native/geth/geth
cat > /var/lib/ethereum-pos-native/geth/geth/static-nodes.json << 'EOF'
[
  "enode://abc123...@<NODE0_HOST>:30303"
]
EOF
```

> `static-nodes.json`은 Geth 시작 전에 작성해야 합니다.
> Geth 실행 중에는 `geth attach --exec 'admin.addPeer("enode://...")'` 로 추가합니다.

### Step 3 — node0에도 node1 enode 추가

node1 enode 확인 후 node0의 `static-nodes.json`에 추가:
```bash
# node1에서
geth attach --exec "admin.nodeInfo.enode" /var/lib/ethereum-pos-native/geth/geth.ipc
# 출력된 enode의 IP를 NODE1_HOST로 교체

# node0에서 (런타임 추가)
geth attach --exec 'admin.addPeer("enode://<node1-pubkey>@<NODE1_HOST>:30303")' \
    /var/lib/ethereum-pos-native/geth/geth.ipc
```

### Step 4 — 연결 확인

양쪽 노드에서:
```bash
geth attach --exec "net.peerCount" /var/lib/ethereum-pos-native/geth/geth.ipc
# 기대값: 1 이상

geth attach --exec "admin.peers" /var/lib/ethereum-pos-native/geth/geth.ipc
# 상대 노드 정보 포함 여부 확인
```

### env 업데이트 후 서비스 반영

peer 정보를 env에 반영하려면 다음 두 가지 방법 중 하나를 사용합니다.

**방법 A — 프로젝트 .env 수정 후 재설치 (권장)**

```bash
# 1. 프로젝트 .env 수정
nano .env
# STATIC_BOOTNODES=enode://<pubkey>@<peer-ip>:30303

# 2. 서비스 재설치
#    /etc/ethereum-pos-native/<NODE_NAME>.env 에 .env 내용이 복사됨
#    geth-pos-wrapper가 이 env를 읽어 --bootnodes 조건부 추가
sudo npm run install:services

# 3. 서비스 재시작
sudo npm run stop && sudo npm run start
```

**방법 B — /etc/ethereum-pos-native/<NODE_NAME>.env 직접 수정**

프로젝트 레포와 동기화를 책임져야 하므로, 임시 운영 시에만 사용하세요.

```bash
# 1. env 파일 직접 수정
sudo nano /etc/ethereum-pos-native/eth-pos-node0.env
# STATIC_BOOTNODES=enode://<pubkey>@<peer-ip>:30303

# 2. 서비스 재시작 (daemon-reload 불필요, env는 서비스 시작 시 재로드됨)
sudo npm run stop && sudo npm run start
```

> **중요:** `install:services`는 `.env` 내용을 `/etc/ethereum-pos-native/<NODE_NAME>.env`로 덮어씁니다.
> 방법 B로 직접 수정한 내용은 다음 `install:services` 실행 시 덮어쓰여집니다.

---

## Prysm Beacon peer 연결

### Step 1 — node0 ENR 확인

**node0에서:**
```bash
curl -s http://localhost:3500/eth/v1/node/identity | jq .
```

출력:
```json
{
  "data": {
    "peer_id": "16Uiu2HAmXXX...",
    "enr": "enr:-MK4Q...",
    "p2p_addresses": [
      "/ip4/<NODE0_HOST>/tcp/13000/p2p/16Uiu2HAmXXX..."
    ]
  }
}
```

### Step 2 — node1 env 업데이트

node1의 `.env`:
```dotenv
STATIC_ENRS=enr:-MK4Q...  # node0의 ENR
```

또는 multiaddr 형식으로 `--peer` 플래그 사용 (서비스 파일 수동 편집):
```
/ip4/<NODE0_HOST>/tcp/13000/p2p/16Uiu2HAmXXX...
```

### Step 3 — env 업데이트 후 서비스 반영

```bash
# 방법 A (권장): 프로젝트 .env 수정 → install:services → 재시작
nano .env           # STATIC_ENRS=enr:-MK4Q...
sudo npm run install:services
sudo npm run stop && sudo npm run start

# 방법 B: /etc 직접 수정 → 재시작
sudo nano /etc/ethereum-pos-native/eth-pos-node1.env
sudo npm run stop && sudo npm run start
```

### Step 4 — 연결 확인

```bash
curl -s http://localhost:3500/eth/v1/node/peers | jq '.data | length'
# 기대값: 1 이상

curl -s http://localhost:3500/eth/v1/node/peers | jq '.data[].peer_id'
# 상대 노드 peer_id 포함 여부 확인
```

---

## 연결 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| Geth `peerCount=0` | 방화벽 차단 또는 enode IP 오류 | 방화벽 확인, IP 교체 |
| Geth peer 발견 후 즉시 드롭 | genesis.json 불일치 | SHA256 비교 후 재초기화 |
| Beacon `peers=0` | ENR IP 오류 또는 방화벽 | ENR 내 IP 확인, 13000/12000 포트 |
| finality 미달성 | peer 연결 없음 | 양쪽 연결 확인 후 3 epoch 대기 |

---

## peer 연결 없는 단일 노드 finality

validator가 64개인 경우, 한 노드에 validator가 32개만 있으면 다른 32개가 없어 2/3 quorum을 달성하지 못합니다.

**finality 달성 조건**: 두 노드의 validator가 모두 참여해야 합니다.
- node0: validator 0~31 (32개)
- node1: validator 32~63 (32개)
- 합계 64개 → 2/3 이상 attestation 가능
