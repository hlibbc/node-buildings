# config/

네트워크 설정 파일 보관 디렉토리.

## 생성 파일 (02-generate-network-config.sh 실행 시 `/etc/ethereum-pos-native/` 에 생성)

| 파일 | 설명 |
|------|------|
| `config.yml` | Prysm beacon chain config — chain ID, fork 버전, 슬롯 파라미터 |
| `genesis.json` | Geth genesis block (prysmctl이 beacon root precompile 등 수정 후 최종본) |
| `genesis.ssz` | Prysm beacon genesis state — validator 64개 pre-funded |
| `jwtsecret` | Engine API JWT secret (openssl rand -hex 32 생성, 모든 노드 공유) |

## 예제 파일 (참고용)

| 파일 | 설명 |
|------|------|
| `config.yml.example` | config.yml 전체 예제 |
| `prefund.json.example` | prefunded account 형식 예제 |
| `jwtsecret.example` | jwtsecret 형식 예제 (절대 운영에 사용 금지) |

## 주의사항

- `02-generate-network-config.sh`는 **node0에서만** 실행한다.
- 생성된 4개 파일을 node1에 복사한 후 `03-init-geth.sh`를 실행한다.
- node1에서 독자적으로 genesis를 재생성하면 다른 체인이 된다.
- `jwtsecret`이 다르면 beacon → geth Engine API 연결이 실패한다.
- `genesis.ssz`가 다르면 beacon chain이 다른 genesis 상태에서 시작한다.

## node1에 config 복사 방법

```bash
# node0에서 실행
scp -r /etc/ethereum-pos-native/ <node1-user>@<node1-ip>:/etc/ethereum-pos-native/
```

자세한 내용 → [docs/ethereum-pos-native/native-setup.md](../../../docs/ethereum-pos-native/native-setup.md)
