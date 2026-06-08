# config/

Docker Compose 컨테이너들이 공유하는 네트워크 설정 파일.
모든 컨테이너는 `./config:/config:ro` 로 마운트합니다.

## 생성 파일 (00-generate-config.sh → create-genesis 서비스)

| 파일 | 생성 방법 | 재생성 가능 여부 |
|------|-----------|-----------------|
| `config.yml` | `00-generate-config.sh` (host 스크립트) | 아니오 (재생성 시 fork 파라미터 불일치) |
| `genesis.json` | `00-generate-config.sh` (host 스크립트) | 아니오 (재생성 시 다른 체인) |
| `genesis.ssz` | `create-genesis` Docker 서비스 | 아니오 (재생성 시 validator 불일치) |
| `jwtsecret` | `00-generate-config.sh` (host 스크립트) | 재생성 시 모든 컨테이너 재시작 필요 |

## 예제 파일

| 파일 | 설명 |
|------|------|
| `config.yml.example` | beacon chain config 예제 |
| `prefund.json.example` | genesis prefunded account 설정 예제 |

## 주의

- 이 디렉토리의 실제 파일들은 `.gitignore`에 추가하거나 버전 관리에 주의하세요.
- `jwtsecret`은 비밀 키입니다. 외부에 노출되지 않도록 관리하세요.
- `genesis.json` / `genesis.ssz` / `config.yml`은 한 번 생성 후 변경하면 체인이 깨집니다.
