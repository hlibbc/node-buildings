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

```bash
# Linux
ss -tlnp | grep <GETH_HTTP_PORT>

# macOS
netstat -an | grep <GETH_HTTP_PORT>
```

- consensus: `127.0.0.1:<GETH_HTTP_PORT>` 리슨 (외부 노출 없음)
- rpc: `0.0.0.0:<GETH_HTTP_PORT>` 리슨

---

## RPC 접속

```bash
./geth/v1.13.15/geth attach http://<rpc-ip>:<GETH_HTTP_PORT>
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

```bash
# consensus
tail -f geth.log | grep -E "mined|sealed|commit|peer"

# rpc
tail -f geth-rpc.log | grep -E "imported|peer|synced"
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
