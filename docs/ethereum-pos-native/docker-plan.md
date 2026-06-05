# docker-plan.md — Docker 방식 전환 계획

Native 방식 안정화 후 Docker Compose로 옮길 때 고려사항.
**현재 이 단계는 구현하지 않습니다.**

---

## 왜 Native 먼저인가

| 항목 | Native | Docker |
|------|--------|--------|
| Execution-Consensus 연결 추적 | 직접 관찰 가능 | 컨테이너 네트워크 추상화 |
| genesis/jwtsecret 경로 | `/etc/` 직관적 | volume mount 복잡 |
| 포트 바인딩 확인 | `ss -tlnp` 직접 확인 | iptables/bridge 간접 |
| 재시작/finality 관찰 | journalctl | docker logs |
| 디버깅 속도 | 빠름 | 레이어 추가됨 |

---

## Docker 전환 시 고려사항

### 1. 버전 고정

```yaml
# 나쁜 예 (versions.lock 취지 위반)
image: "ethereum/client-go:latest"
image: "gcr.io/prysmaticlabs/prysm/beacon-chain:stable"

# 올바른 예
image: "ethereum/client-go:v1.14.12"
image: "gcr.io/prysmaticlabs/prysm/beacon-chain:v5.3.2"
```

### 2. genesis/config 공유

두 노드가 동일한 genesis.json, genesis.ssz, jwtsecret을 사용해야 합니다.

방법:
- Docker Volume을 외부(named volume 또는 bind mount)로 공유
- 컨테이너 내부에서 재생성 금지

```yaml
# node0
volumes:
  - ./config:/config:ro  # 읽기 전용

# node1
volumes:
  - ./config:/config:ro  # 동일 config 디렉토리
```

### 3. validator 중복 방지

```yaml
# node0 validator
command:
  - --interop-start-index=0
  - --interop-num-validators=32

# node1 validator
command:
  - --interop-start-index=32
  - --interop-num-validators=32
```

### 4. peer 연결

Docker 내부 IP 하드코딩 금지:

```yaml
# 나쁜 예
- --bootnodes=enode://<pubkey>@172.21.0.6:30303  # 내부 IP

# 올바른 예
# 컨테이너 이름으로 참조 (같은 Docker network 내)
- --bootnodes=enode://<pubkey>@geth-node0:30303
# 또는 env 변수 주입
- --bootnodes=${PEER_ENODE}
```

### 5. authrpc 보안

Docker에서도 authrpc는 컨테이너 내부에서만 접근 가능하도록:

```yaml
# Geth
- --authrpc.addr=0.0.0.0  # 컨테이너 내부에서 0.0.0.0 OK
# ports에 authrpc 포트 노출 금지
# ports:
#   - "8551:8551"  ← 이렇게 하지 않는다

# Beacon이 geth 컨테이너에 접근할 때 컨테이너 이름 사용
- --execution-endpoint=http://geth:8551
```

### 6. force-clear-db 금지

```yaml
# 나쁜 예 (데이터 삭제 위험)
command:
  - --force-clear-db

# 올바른 예: 이 플래그 없음
```

---

## Docker 장단점

**장점:**
- 재현성: 동일한 이미지로 어디서든 동일 환경
- 격리: 호스트 환경 오염 없음
- 업그레이드: 이미지 태그만 변경
- multi-node: 로컬에서 여러 노드 테스트 용이

**단점:**
- 네트워크 레이어 추가 (bridge, iptables)
- 포트 매핑 복잡성
- genesis/config 배포가 volume mount로 간접화
- 디버깅 시 컨테이너 진입 단계 추가

---

## 구현 우선순위

1. Native 방식으로 finality 달성 및 Arbitrum L2 연동 검증 ← **현재 단계**
2. Native 방식 문서화 완료
3. Docker Compose 작성 (Native 절차를 1:1 매핑)
4. docker-compose.yml 검증 (동일 genesis로 동일 결과)
