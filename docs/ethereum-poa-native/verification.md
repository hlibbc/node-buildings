# 검증 명령 모음

rpc 노드 HTTP RPC 기준. `<rpc-ip>`, `<port>` 는 rpc.env의 값으로 대체.

---

## 프로세스 상태

```bash
./setup.sh --env=consensus.env status
./setup-rpc-node.sh --env=rpc.env status
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

```javascript
net.peerCount
```

- 기대값: `1` 이상 (consensus ↔ rpc 연결)
- `0` 이면 `STATIC_PEER_ENODE` 값 및 IP/포트 확인

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

## 정지 / 재기동

```bash
# consensus
./setup.sh --env=consensus.env stop
./setup.sh --env=consensus.env run-consensus

# rpc
./setup-rpc-node.sh --env=rpc.env stop
./setup-rpc-node.sh --env=rpc.env run
```
