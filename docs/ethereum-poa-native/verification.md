# 검증 명령 모음

rpc 노드 HTTP RPC 기준. `<rpc-ip>`, `<port>` 는 rpc 인스턴스 `.env` 의 `GETH_HTTP_PORT` 값으로 대체.

---

## 프로세스 상태

consensus 인스턴스에서:

```bash
./setup.sh status
# 또는
ps -ef | grep '[g]eth'
```

rpc 인스턴스에서:

```bash
./setup-rpc-node.sh status
# 또는
ps -ef | grep '[g]eth'
```

- 기대값: `Geth is running.` + 프로세스 라인 출력

---

## 포트 리슨 확인

consensus 인스턴스에서:

```bash
# Linux
ss -tlnp | grep <consensus GETH_HTTP_PORT>
# macOS
netstat -an | grep <consensus GETH_HTTP_PORT>
```

- 기대값: `127.0.0.1:<port>` — 외부 미노출

rpc 인스턴스에서:

```bash
# Linux
ss -tlnp | grep <rpc GETH_HTTP_PORT>
# macOS
netstat -an | grep <rpc GETH_HTTP_PORT>
```

- 기대값: `0.0.0.0:<port>` — 외부 접근 가능

---

## RPC 접속

rpc 인스턴스에 대해 외부에서 접속:

```bash
# geth attach
./geth/v1.13.15/geth attach http://<rpc-ip>:<GETH_HTTP_PORT>

# curl (간단 확인)
curl -s -X POST http://<rpc-ip>:<GETH_HTTP_PORT> \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

---

## genesis 동일성 검증

consensus / rpc 양쪽 인스턴스에서 각각 실행 후 hash 비교:

```bash
jq -S . ./genesis/genesis.json | sha256sum
# 또는
sha256sum ./genesis/genesis.json
```

- 기대값: 양쪽 hash 가 동일해야 함. 다르면 rpc node 의 `genesis.json` 이 잘못 배포된 것 — `clean` 후 재배포·재초기화 필요

init 후 콘솔에서 추가 확인:

```javascript
eth.getBlock(0).hash              // 양쪽 노드에서 동일해야 함
eth.chainId()                     // .env CHAIN_ID 와 일치 확인
admin.nodeInfo.protocols.eth.network  // networkId 확인
```

---

## [ ] chainId 확인

```javascript
eth.chainId()
```

- 기대값: `.env` 의 `CHAIN_ID` 와 동일 (hex 문자열, 예: `"0x3039"`)

---

## [ ] 블록 생성 확인

```javascript
eth.blockNumber
```

- 기대값: 1 이상, 약 2초 주기로 증가 (Clique period: 2)

---

## [ ] peer 연결 확인

현재 구현(`static-nodes.json` 방식)은 geth 1.13.15 에서 deprecated 되어 자동 연결이 성립하지 않는다.
peer 연결이 안 된 경우 rpc 콘솔(`./setup-rpc-node.sh attach`)에서 수동으로 추가한다.

```javascript
// peer 수동 추가 (IP 가 127.0.0.1 이면 consensus 실제 IP 로 교체 필수)
admin.addPeer("enode://<pubkey>@<consensus-real-ip>:<GETH_PORT>")
// true

net.peerCount    // 기대값: 1 이상
admin.peers      // 기대값: [{enode: "...", ...}]
```

- `net.peerCount` 가 `0` 이면: enode 에 실제 도달 가능한 IP 가 지정되어 있는지 확인 (`127.0.0.1` 이면 실제 IP 로 교체)

---

## 로그 확인

consensus 인스턴스에서:

```bash
tail -f geth.log | grep --line-buffered -E "mined|sealed|commit|peer"
```

rpc 인스턴스에서:

```bash
tail -f geth-rpc.log | grep --line-buffered -E "imported|peer|synced"
```

- consensus: `Successfully sealed new block` 또는 `mined potential block` 출력 확인
- rpc: `Imported new chain segment` 출력 확인

---

## 로그 전체 확인

```bash
# consensus 인스턴스
tail -100 geth.log

# rpc 인스턴스
tail -100 geth-rpc.log
```

---

## 정지 / 재기동

consensus 인스턴스에서:

```bash
./setup.sh stop
./setup.sh run-consensus
```

rpc 인스턴스에서:

```bash
./setup-rpc-node.sh stop
./setup-rpc-node.sh run
```

강제 종료가 필요한 경우 (datadir 경로 기준):

```bash
pkill -2 -f "geth.*--datadir.*./var/consensus/data"   # consensus
pkill -2 -f "geth.*--datadir.*./var/rpc/data"         # rpc
```
